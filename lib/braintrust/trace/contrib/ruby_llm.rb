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

      # Wrap a RubyLLM chat instance to automatically create spans for chat requests
      # Supports both synchronous and streaming requests
      # @param chat [RubyLLM::Chat] the RubyLLM chat instance to wrap
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
      def self.wrap(chat, tracer_provider: nil)
        tracer_provider ||= ::OpenTelemetry.tracer_provider

        # Create a wrapper module that intercepts chat.ask
        wrapper = Module.new do
          define_method(:ask) do |prompt = nil, **params, &block|
            tracer = tracer_provider.tracer("braintrust")

            # Determine if this is a streaming request (block provided)
            is_streaming = !block.nil?

            if is_streaming
              # Handle streaming
              aggregated_chunks = []
              metadata = {
                "provider" => "ruby_llm",
                "stream" => true
              }

              # Start span
              span = tracer.start_span("ruby_llm.chat.ask")

              # Extract model from chat instance if available
              if respond_to?(:model) && self.model
                model = self.model.respond_to?(:id) ? self.model.id : self.model.to_s
                metadata["model"] = model
              end

              # Build input - RubyLLM maintains conversation history
              input_messages = []
              if respond_to?(:messages) && messages && messages.any?
                input_messages = messages.map { |m| m.respond_to?(:to_h) ? m.to_h : m }
              end
              # Add current prompt
              input_messages << {role: "user", content: prompt} if prompt

              Braintrust::Trace::RubyLLM.set_json_attr(span, "braintrust.input_json", input_messages) if input_messages.any?
              Braintrust::Trace::RubyLLM.set_json_attr(span, "braintrust.metadata", metadata)

              # Call original with wrapper block
              begin
                result = super(prompt, **params) do |chunk|
                  aggregated_chunks << chunk
                  block.call(chunk)
                end
              rescue => e
                span.record_exception(e)
                span.status = ::OpenTelemetry::Trace::Status.error("RubyLLM error: #{e.message}")
                span.finish
                raise
              end

              # Aggregate streaming output
              unless aggregated_chunks.empty?
                # Aggregate content from chunks
                aggregated_content = aggregated_chunks.map { |c|
                  c.respond_to?(:content) ? c.content : c.to_s
                }.join

                output = [{
                  role: "assistant",
                  content: aggregated_content
                }]
                Braintrust::Trace::RubyLLM.set_json_attr(span, "braintrust.output_json", output)

                # Try to extract usage from the result or last chunk
                if result.respond_to?(:usage) && result.usage
                  metrics = Braintrust::Trace::RubyLLM.parse_usage_tokens(result.usage)
                  Braintrust::Trace::RubyLLM.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
                end
              end

              span.finish
              result
            else
              # Handle non-streaming
              tracer.in_span("ruby_llm.chat.ask") do |span|
                # Initialize metadata hash
                metadata = {
                  "provider" => "ruby_llm"
                }

                # Extract model from chat instance if available
                if respond_to?(:model) && self.model
                  model = self.model.respond_to?(:id) ? self.model.id : self.model.to_s
                  metadata["model"] = model
                end

                # Capture tools if available - use provider's tool_for method to get proper format
                if respond_to?(:tools) && tools && tools.any?
                  # Get the provider to determine the correct format
                  provider = instance_variable_get(:@provider) if instance_variable_defined?(:@provider)

                  metadata["tools"] = tools.map do |name, tool|
                    tool_schema = nil

                    # Use provider-specific tool_for method if available
                    if provider
                      begin
                        # Try OpenAI format
                        tool_schema = if provider.is_a?(RubyLLM::Providers::OpenAI)
                          RubyLLM::Providers::OpenAI::Tools.tool_for(tool)
                        # Try Anthropic format
                        elsif defined?(RubyLLM::Providers::Anthropic) && provider.is_a?(RubyLLM::Providers::Anthropic)
                          RubyLLM::Providers::Anthropic::Tools.tool_for(tool)
                        # Fallback to manual construction using params_schema
                        elsif tool.respond_to?(:params_schema) && tool.params_schema
                          {
                            "type" => "function",
                            "function" => {
                              "name" => tool.name.to_s,
                              "description" => tool.description,
                              "parameters" => tool.params_schema
                            }
                          }
                        else
                          # Minimal fallback
                          {
                            "type" => "function",
                            "function" => {
                              "name" => tool.name.to_s,
                              "description" => tool.description,
                              "parameters" => {}
                            }
                          }
                        end
                      rescue
                        # If anything fails, use basic format
                        tool_schema = {
                          "type" => "function",
                          "function" => {
                            "name" => tool.name.to_s,
                            "description" => tool.description,
                            "parameters" => (tool.respond_to?(:params_schema) && tool.params_schema) ? tool.params_schema : {}
                          }
                        }
                      end
                    else
                      # No provider, use basic format with params_schema if available
                      tool_schema = {
                        "type" => "function",
                        "function" => {
                          "name" => tool.name.to_s,
                          "description" => tool.description,
                          "parameters" => (tool.respond_to?(:params_schema) && tool.params_schema) ? tool.params_schema : {}
                        }
                      }
                    end

                    # Strip RubyLLM-specific fields to match native OpenAI format
                    if tool_schema && tool_schema.dig("function", "parameters")
                      tool_params = tool_schema["function"]["parameters"]
                      # Remove strict and additionalProperties which are RubyLLM-specific
                      tool_params.delete("strict") if tool_params.is_a?(Hash)
                      tool_params.delete("additionalProperties") if tool_params.is_a?(Hash)
                    end

                    tool_schema
                  end
                end

                # Build input - RubyLLM maintains conversation history
                input_messages = []
                if respond_to?(:messages) && messages && messages.any?
                  input_messages = messages.map { |m| m.respond_to?(:to_h) ? m.to_h : m }
                end
                # Add current prompt
                input_messages << {role: "user", content: prompt} if prompt

                # Set input messages as JSON
                Braintrust::Trace::RubyLLM.set_json_attr(span, "braintrust.input_json", input_messages) if input_messages.any?

                # Remember the message count before the call
                messages_before_count = (respond_to?(:messages) && messages) ? messages.length : 0

                # Call the original method
                response = super(prompt, **params)

                # Format output to match OpenAI's choices[] structure
                if response
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
                  if respond_to?(:messages) && messages
                    # Get the assistant message with tool calls (if any)
                    assistant_msg = messages[(messages_before_count + 1)..].find { |m| m.role.to_s == "assistant" && m.respond_to?(:tool_calls) && m.tool_calls&.any? }

                    if assistant_msg&.tool_calls&.any?
                      message["tool_calls"] = assistant_msg.tool_calls.map do |id, tc|
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
                      message["content"] = nil if message["tool_calls"]
                    end
                  end

                  # Format as OpenAI choices[] structure
                  output = [{
                    "index" => 0,
                    "message" => message,
                    "finish_reason" => message["tool_calls"] ? "tool_calls" : "stop"
                  }]

                  Braintrust::Trace::RubyLLM.set_json_attr(span, "braintrust.output_json", output)
                end

                # Set metrics (token usage)
                # RubyLLM stores usage data directly in the response object/hash
                if response.respond_to?(:to_h)
                  response_hash = response.to_h
                  # Build usage hash from RubyLLM's token fields
                  usage = {
                    "input_tokens" => response_hash[:input_tokens],
                    "output_tokens" => response_hash[:output_tokens],
                    "cached_tokens" => response_hash[:cached_tokens],
                    "cache_creation_tokens" => response_hash[:cache_creation_tokens]
                  }.compact

                  unless usage.empty?
                    metrics = Braintrust::Trace::RubyLLM.parse_usage_tokens(usage)
                    Braintrust::Trace::RubyLLM.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
                  end
                end

                # Set metadata
                Braintrust::Trace::RubyLLM.set_json_attr(span, "braintrust.metadata", metadata)

                response
              end
            end
          end
        end

        # Prepend the wrapper to the chat instance
        chat.singleton_class.prepend(wrapper)
        chat
      end
    end
  end
end
