# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

module Braintrust
  module Trace
    module RubyLLM
      # Helper to safely set a JSON attribute on a span
      # Only sets the attribute if obj is present
      # @param span [OpenTelemetry::Trace::Span] the span to set attribute on
      # @param attr_name [String] the attribute name (e.g., "braintrust.output_json")
      # @param obj [Object] the object to serialize to JSON
      # @return [void]
      def self.set_json_attr(span, attr_name, obj)
        return unless obj
        span.set_attribute(attr_name, JSON.generate(obj))
      rescue => e
        warn "Failed to serialize #{attr_name}: #{e.message}"
      end

      # Parse usage tokens from RubyLLM response
      # Maps to Braintrust standard names:
      # - input_tokens/prompt_tokens → prompt_tokens
      # - output_tokens/completion_tokens → completion_tokens
      # - total_tokens → tokens
      #
      # @param usage [Hash, Object] usage object from RubyLLM response
      # @return [Hash<String, Integer>] metrics hash with normalized names
      def self.parse_usage_tokens(usage)
        metrics = {}
        return metrics unless usage

        # Convert to hash if it's an object
        usage_hash = usage.respond_to?(:to_h) ? usage.to_h : usage
        return metrics unless usage_hash.is_a?(Hash)

        usage_hash.each do |key, value|
          next unless value.is_a?(Numeric)
          key_str = key.to_s

          case key_str
          when "input_tokens", "prompt_tokens"
            metrics["prompt_tokens"] ||= value.to_i
          when "output_tokens", "completion_tokens"
            metrics["completion_tokens"] ||= value.to_i
          when "total_tokens", "tokens"
            metrics["tokens"] ||= value.to_i
          when "cached_tokens"
            metrics["prompt_cached_tokens"] = value.to_i
          when "cache_creation_tokens"
            metrics["prompt_cache_creation_tokens"] = value.to_i
          else
            # Keep other numeric fields as-is (future-proofing)
            metrics[key_str] = value.to_i
          end
        end

        # Calculate total if not provided
        if !metrics.key?("tokens") && metrics.key?("prompt_tokens") && metrics.key?("completion_tokens")
          metrics["tokens"] = metrics["prompt_tokens"] + metrics["completion_tokens"]
        end

        metrics
      end

      # Wrap RubyLLM to automatically create spans for chat requests
      # Supports both synchronous and streaming requests
      #
      # Usage:
      #   # Wrap the class once (affects all future instances):
      #   Braintrust::Trace::RubyLLM.wrap
      #
      #   # Or wrap a specific instance:
      #   chat = RubyLLM.chat(model: "gpt-4o-mini")
      #   Braintrust::Trace::RubyLLM.wrap(chat)
      #
      # @param chat [RubyLLM::Chat, nil] the RubyLLM chat instance to wrap (if nil, wraps the class)
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
      def self.wrap(chat = nil, tracer_provider: nil)
        tracer_provider ||= ::OpenTelemetry.tracer_provider

        # If no chat instance provided, wrap the class globally
        if chat.nil?
          return if defined?(RubyLLM::Chat) && RubyLLM::Chat.instance_variable_get(:@braintrust_wrapped)
          wrap_class(tracer_provider)
          RubyLLM::Chat.instance_variable_set(:@braintrust_wrapped, true) if defined?(RubyLLM::Chat)
          return nil
        end

        # Check if already wrapped to make this idempotent
        return chat if chat.instance_variable_get(:@braintrust_wrapped)

        # Create a wrapper module that intercepts chat.ask
        wrapper = create_wrapper_module(tracer_provider)

        # Mark as wrapped and prepend the wrapper to the chat instance
        chat.instance_variable_set(:@braintrust_wrapped, true)
        chat.singleton_class.prepend(wrapper)
        chat
      end

      # Wrap the RubyLLM::Chat class globally
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
      def self.wrap_class(tracer_provider)
        return unless defined?(RubyLLM::Chat)

        wrapper = create_wrapper_module(tracer_provider)
        RubyLLM::Chat.prepend(wrapper)
      end

      # Create the wrapper module that intercepts chat.ask
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
      # @return [Module] the wrapper module
      def self.create_wrapper_module(tracer_provider)
        Module.new do
          define_method(:ask) do |prompt = nil, **params, &block|
            tracer = tracer_provider.tracer("braintrust")

            if block
              # Handle streaming request
              wrapped_block = proc do |chunk|
                block.call(chunk)
              end
              Braintrust::Trace::RubyLLM.handle_streaming_ask(self, tracer, prompt, params, block) do |aggregated_chunks|
                super(prompt, **params) do |chunk|
                  aggregated_chunks << chunk
                  wrapped_block.call(chunk)
                end
              end
            else
              # Handle non-streaming request
              Braintrust::Trace::RubyLLM.handle_non_streaming_ask(self, tracer, prompt, params) do
                super(prompt, **params)
              end
            end
          end
        end
      end

      # Handle streaming chat request with tracing
      # @param chat [RubyLLM::Chat] the chat instance
      # @param tracer [OpenTelemetry::Trace::Tracer] the tracer
      # @param prompt [String, nil] the user prompt
      # @param params [Hash] additional parameters
      # @param block [Proc] the streaming block
      def self.handle_streaming_ask(chat, tracer, prompt, params, block)
        # Start span immediately for accurate timing
        span = tracer.start_span("ruby_llm.chat.ask")

        aggregated_chunks = []

        # Extract metadata and build input messages
        metadata = extract_metadata(chat, stream: true)
        input_messages = build_input_messages(chat, prompt)

        # Set input and metadata
        set_json_attr(span, "braintrust.input_json", input_messages) if input_messages.any?
        set_json_attr(span, "braintrust.metadata", metadata)

        # Call original method, passing aggregated_chunks to the block
        begin
          result = yield aggregated_chunks
        rescue => e
          span.record_exception(e)
          span.status = ::OpenTelemetry::Trace::Status.error("RubyLLM error: #{e.message}")
          span.finish
          raise
        end

        # Set output and metrics from aggregated chunks
        capture_streaming_output(span, aggregated_chunks, result)
        span.finish
        result
      end

      # Handle non-streaming chat request with tracing
      # @param chat [RubyLLM::Chat] the chat instance
      # @param tracer [OpenTelemetry::Trace::Tracer] the tracer
      # @param prompt [String, nil] the user prompt
      # @param params [Hash] additional parameters
      def self.handle_non_streaming_ask(chat, tracer, prompt, params)
        # Start span immediately for accurate timing
        span = tracer.start_span("ruby_llm.chat.ask")

        begin
          # Extract metadata and build input messages
          metadata = extract_metadata(chat)
          input_messages = build_input_messages(chat, prompt)
          set_json_attr(span, "braintrust.input_json", input_messages) if input_messages.any?

          # Remember message count before the call (for tool call detection)
          messages_before_count = (chat.respond_to?(:messages) && chat.messages) ? chat.messages.length : 0

          # Call the original method
          response = yield

          # Capture output and metrics
          capture_non_streaming_output(span, chat, response, messages_before_count)

          # Set metadata
          set_json_attr(span, "braintrust.metadata", metadata)

          response
        ensure
          span.finish
        end
      end

      # Extract metadata from chat instance (provider, model, tools, stream flag)
      # @param chat [RubyLLM::Chat] the chat instance
      # @param stream [Boolean] whether this is a streaming request
      # @return [Hash] metadata hash
      def self.extract_metadata(chat, stream: false)
        metadata = {"provider" => "ruby_llm"}
        metadata["stream"] = true if stream

        # Extract model
        if chat.respond_to?(:model) && chat.model
          model = chat.model.respond_to?(:id) ? chat.model.id : chat.model.to_s
          metadata["model"] = model
        end

        # Extract tools (only for non-streaming)
        if !stream && chat.respond_to?(:tools) && chat.tools&.any?
          metadata["tools"] = extract_tools_metadata(chat)
        end

        metadata
      end

      # Extract tools metadata from chat instance
      # @param chat [RubyLLM::Chat] the chat instance
      # @return [Array<Hash>] array of tool schemas
      def self.extract_tools_metadata(chat)
        provider = chat.instance_variable_get(:@provider) if chat.instance_variable_defined?(:@provider)

        chat.tools.map do |_name, tool|
          format_tool_schema(tool, provider)
        end
      end

      # Format a tool into OpenAI-compatible schema
      # @param tool [Object] the tool object
      # @param provider [Object, nil] the provider instance
      # @return [Hash] tool schema
      def self.format_tool_schema(tool, provider)
        tool_schema = nil

        # Use provider-specific tool_for method if available
        if provider
          begin
            tool_schema = if provider.is_a?(RubyLLM::Providers::OpenAI)
              RubyLLM::Providers::OpenAI::Tools.tool_for(tool)
            elsif defined?(RubyLLM::Providers::Anthropic) && provider.is_a?(RubyLLM::Providers::Anthropic)
              RubyLLM::Providers::Anthropic::Tools.tool_for(tool)
            elsif tool.respond_to?(:params_schema) && tool.params_schema
              build_basic_tool_schema(tool)
            else
              build_minimal_tool_schema(tool)
            end
          rescue
            # If anything fails, use basic format
            tool_schema = (tool.respond_to?(:params_schema) && tool.params_schema) ? build_basic_tool_schema(tool) : build_minimal_tool_schema(tool)
          end
        else
          # No provider, use basic format with params_schema if available
          tool_schema = (tool.respond_to?(:params_schema) && tool.params_schema) ? build_basic_tool_schema(tool) : build_minimal_tool_schema(tool)
        end

        # Strip RubyLLM-specific fields to match native OpenAI format
        if tool_schema&.dig("function", "parameters")
          tool_params = tool_schema["function"]["parameters"]
          tool_params.delete("strict") if tool_params.is_a?(Hash)
          tool_params.delete("additionalProperties") if tool_params.is_a?(Hash)
        end

        tool_schema
      end

      # Build a basic tool schema with parameters
      # @param tool [Object] the tool object
      # @return [Hash] tool schema
      def self.build_basic_tool_schema(tool)
        {
          "type" => "function",
          "function" => {
            "name" => tool.name.to_s,
            "description" => tool.description,
            "parameters" => tool.params_schema
          }
        }
      end

      # Build a minimal tool schema without parameters
      # @param tool [Object] the tool object
      # @return [Hash] tool schema
      def self.build_minimal_tool_schema(tool)
        {
          "type" => "function",
          "function" => {
            "name" => tool.name.to_s,
            "description" => tool.description,
            "parameters" => {}
          }
        }
      end

      # Build input messages array from chat history and prompt
      # @param chat [RubyLLM::Chat] the chat instance
      # @param prompt [String, nil] the user prompt
      # @return [Array<Hash>] array of message hashes
      def self.build_input_messages(chat, prompt)
        input_messages = []

        # Add conversation history
        if chat.respond_to?(:messages) && chat.messages&.any?
          input_messages = chat.messages.map { |m| m.respond_to?(:to_h) ? m.to_h : m }
        end

        # Add current prompt
        input_messages << {role: "user", content: prompt} if prompt

        input_messages
      end

      # Capture streaming output and metrics
      # @param span [OpenTelemetry::Trace::Span] the span
      # @param aggregated_chunks [Array] the aggregated chunks
      # @param result [Object] the result object
      def self.capture_streaming_output(span, aggregated_chunks, result)
        return if aggregated_chunks.empty?

        # Aggregate content from chunks
        aggregated_content = aggregated_chunks.map { |c|
          c.respond_to?(:content) ? c.content : c.to_s
        }.join

        output = [{
          role: "assistant",
          content: aggregated_content
        }]
        set_json_attr(span, "braintrust.output_json", output)

        # Try to extract usage from the result
        if result.respond_to?(:usage) && result.usage
          metrics = parse_usage_tokens(result.usage)
          set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
        end
      end

      # Capture non-streaming output and metrics
      # @param span [OpenTelemetry::Trace::Span] the span
      # @param chat [RubyLLM::Chat] the chat instance
      # @param response [Object] the response object
      # @param messages_before_count [Integer] message count before the call
      def self.capture_non_streaming_output(span, chat, response, messages_before_count)
        return unless response

        # Build message object from response
        message = {
          "role" => "assistant",
          "content" => nil
        }

        # Add content if it's a simple text response
        if response.respond_to?(:content) && response.content && !response.content.empty?
          message["content"] = response.content
        end

        # Check if there are tool calls in the messages history
        if chat.respond_to?(:messages) && chat.messages
          assistant_msg = chat.messages[(messages_before_count + 1)..].find { |m|
            m.role.to_s == "assistant" && m.respond_to?(:tool_calls) && m.tool_calls&.any?
          }

          if assistant_msg&.tool_calls&.any?
            message["tool_calls"] = format_tool_calls(assistant_msg.tool_calls)
            message["content"] = nil
          end
        end

        # Format as OpenAI choices[] structure
        output = [{
          "index" => 0,
          "message" => message,
          "finish_reason" => message["tool_calls"] ? "tool_calls" : "stop"
        }]

        set_json_attr(span, "braintrust.output_json", output)

        # Set metrics (token usage)
        if response.respond_to?(:to_h)
          response_hash = response.to_h
          usage = {
            "input_tokens" => response_hash[:input_tokens],
            "output_tokens" => response_hash[:output_tokens],
            "cached_tokens" => response_hash[:cached_tokens],
            "cache_creation_tokens" => response_hash[:cache_creation_tokens]
          }.compact

          unless usage.empty?
            metrics = parse_usage_tokens(usage)
            set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
          end
        end
      end

      # Format tool calls into OpenAI format
      # @param tool_calls [Hash, Array] the tool calls
      # @return [Array<Hash>] formatted tool calls
      def self.format_tool_calls(tool_calls)
        tool_calls.map do |_id, tc|
          # Ensure arguments is a JSON string (OpenAI format)
          args = tc.arguments
          args_string = args.is_a?(String) ? args : JSON.generate(args)

          {
            "id" => tc.id,
            "type" => "function",
            "function" => {
              "name" => tc.name,
              "arguments" => args_string
            }
          }
        end
      end
    end
  end
end
