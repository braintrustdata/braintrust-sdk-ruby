# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"
require_relative "../../../tokens"
require_relative "../../../../logger"

module Braintrust
  module Trace
    module Contrib
      module Github
        module Crmne
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
              Log.debug("Failed to serialize #{attr_name}: #{e.message}")
            end

            # Parse usage tokens from RubyLLM response
            # RubyLLM uses Anthropic-style field naming (input_tokens, output_tokens)
            # @param usage [Hash, Object] usage object from RubyLLM response
            # @return [Hash<String, Integer>] metrics hash with normalized names
            def self.parse_usage_tokens(usage)
              Braintrust::Trace.parse_anthropic_usage_tokens(usage)
            end

            # Wrap RubyLLM to automatically create spans for chat requests
            # Supports both synchronous and streaming requests
            #
            # Usage:
            #   # Wrap the class once (affects all future instances):
            #   Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap
            #
            #   # Or wrap a specific instance:
            #   chat = RubyLLM.chat(model: "gpt-4o-mini")
            #   Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(chat)
            #
            # @param chat [RubyLLM::Chat, nil] the RubyLLM chat instance to wrap (if nil, wraps the class)
            # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
            def self.wrap(chat = nil, tracer_provider: nil)
              tracer_provider ||= ::OpenTelemetry.tracer_provider

              # If no chat instance provided, wrap the class globally via initialize hook
              if chat.nil?
                return if defined?(::RubyLLM::Chat) && ::RubyLLM::Chat.instance_variable_defined?(:@braintrust_wrapper_module)

                # Create module that wraps initialize to auto-wrap each new instance
                wrapper_module = Module.new do
                  define_method(:initialize) do |*args, **kwargs, &block|
                    super(*args, **kwargs, &block)
                    # Auto-wrap this instance during initialization
                    Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(self, tracer_provider: tracer_provider)
                    self
                  end
                end

                # Store reference to wrapper module for cleanup
                ::RubyLLM::Chat.instance_variable_set(:@braintrust_wrapper_module, wrapper_module)
                ::RubyLLM::Chat.prepend(wrapper_module)
                return nil
              end

              # Check if already wrapped to make this idempotent
              return chat if chat.instance_variable_get(:@braintrust_wrapped)

              # Create a wrapper module that intercepts chat.complete
              wrapper = create_wrapper_module(tracer_provider)

              # Mark as wrapped and prepend the wrapper to the chat instance
              chat.instance_variable_set(:@braintrust_wrapped, true)
              chat.singleton_class.prepend(wrapper)

              # Register tool callbacks for tool span creation
              register_tool_callbacks(chat, tracer_provider)

              chat
            end

            # Register callbacks for tool execution tracing
            # @param chat [RubyLLM::Chat] the chat instance
            # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
            def self.register_tool_callbacks(chat, tracer_provider)
              tracer = tracer_provider.tracer("braintrust")

              # Track tool spans by tool_call_id
              tool_spans = {}

              # Start tool span when tool is called
              chat.on_tool_call do |tool_call|
                span = tracer.start_span("ruby_llm.tool.#{tool_call.name}")
                set_json_attr(span, "braintrust.span_attributes", {type: "tool"})
                span.set_attribute("tool.name", tool_call.name)
                span.set_attribute("tool.call_id", tool_call.id)

                # Store tool input
                input = {
                  "name" => tool_call.name,
                  "arguments" => tool_call.arguments
                }
                set_json_attr(span, "braintrust.input_json", input)

                tool_spans[tool_call.id] = span
              end

              # End tool span when result is received
              chat.on_tool_result do |result|
                # Find the most recent tool span (RubyLLM doesn't pass tool_call_id to on_tool_result)
                # The spans are processed in order, so we can use the first unfinished one
                tool_call_id, span = tool_spans.find { |_id, s| s }
                if span
                  # Store tool output
                  set_json_attr(span, "braintrust.output_json", result)
                  span.finish
                  tool_spans.delete(tool_call_id)
                end
              end
            end

            # Unwrap RubyLLM to remove Braintrust tracing
            # For class-level unwrapping, removes the initialize override from the wrapper module
            # For instance-level unwrapping, clears the wrapped flag
            #
            # @param chat [RubyLLM::Chat, nil] the RubyLLM chat instance to unwrap (if nil, unwraps the class)
            def self.unwrap(chat = nil)
              # If no chat instance provided, unwrap the class globally
              if chat.nil?
                if defined?(::RubyLLM::Chat) && ::RubyLLM::Chat.instance_variable_defined?(:@braintrust_wrapper_module)
                  wrapper_module = ::RubyLLM::Chat.instance_variable_get(:@braintrust_wrapper_module)
                  # Redefine initialize to just call super (disables auto-wrapping)
                  # We can't actually remove a prepended module, so we make it a no-op
                  wrapper_module.module_eval do
                    define_method(:initialize) do |*args, **kwargs, &block|
                      super(*args, **kwargs, &block)
                    end
                  end
                  ::RubyLLM::Chat.remove_instance_variable(:@braintrust_wrapper_module)
                end
                return nil
              end

              # Unwrap instance
              chat.remove_instance_variable(:@braintrust_wrapped) if chat.instance_variable_defined?(:@braintrust_wrapped)
              chat
            end

            # Wrap the RubyLLM::Chat class globally
            # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
            def self.wrap_class(tracer_provider)
              return unless defined?(::RubyLLM::Chat)

              wrapper = create_wrapper_module(tracer_provider)
              ::RubyLLM::Chat.prepend(wrapper)
            end

            # Create the wrapper module that intercepts chat.complete
            # We wrap complete() instead of ask() because:
            # - ask() internally calls complete() for the actual API call
            # - ActiveRecord integration (acts_as_chat) calls complete() directly
            # - This ensures all LLM calls are traced regardless of entry point
            #
            # Important: RubyLLM's complete() calls itself recursively for tool execution.
            # We only create a span for the outermost call to avoid duplicate spans.
            # Tool execution is traced separately via on_tool_call/on_tool_result callbacks.
            #
            # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
            # @return [Module] the wrapper module
            def self.create_wrapper_module(tracer_provider)
              Module.new do
                define_method(:complete) do |&block|
                  # Check if we're already inside a traced complete() call
                  # If so, just call super without creating a new span
                  if @braintrust_in_complete
                    if block
                      return super(&block)
                    else
                      return super()
                    end
                  end

                  tracer = tracer_provider.tracer("braintrust")

                  # Mark that we're inside a complete() call
                  @braintrust_in_complete = true

                  begin
                    if block
                      # Handle streaming request
                      wrapped_block = proc do |chunk|
                        block.call(chunk)
                      end
                      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.handle_streaming_complete(self, tracer, block) do |aggregated_chunks|
                        super(&proc do |chunk|
                          aggregated_chunks << chunk
                          wrapped_block.call(chunk)
                        end)
                      end
                    else
                      # Handle non-streaming request
                      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.handle_non_streaming_complete(self, tracer) do
                        super()
                      end
                    end
                  ensure
                    @braintrust_in_complete = false
                  end
                end
              end
            end

            # Handle streaming complete request with tracing
            # @param chat [RubyLLM::Chat] the chat instance
            # @param tracer [OpenTelemetry::Trace::Tracer] the tracer
            # @param block [Proc] the streaming block
            def self.handle_streaming_complete(chat, tracer, block)
              # Start span immediately for accurate timing
              span = tracer.start_span("ruby_llm.chat")

              aggregated_chunks = []

              # Extract metadata and build input messages
              # For complete(), messages are already in chat history (no prompt param)
              metadata = extract_metadata(chat, stream: true)
              input_messages = build_input_messages(chat, nil)

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

            # Handle non-streaming complete request with tracing
            # @param chat [RubyLLM::Chat] the chat instance
            # @param tracer [OpenTelemetry::Trace::Tracer] the tracer
            def self.handle_non_streaming_complete(chat, tracer)
              # Start span immediately for accurate timing
              span = tracer.start_span("ruby_llm.chat")

              begin
                # Extract metadata and build input messages
                # For complete(), messages are already in chat history (no prompt param)
                metadata = extract_metadata(chat)
                input_messages = build_input_messages(chat, nil)
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
                  tool_schema = if provider.is_a?(::RubyLLM::Providers::OpenAI)
                    ::RubyLLM::Providers::OpenAI::Tools.tool_for(tool)
                  elsif defined?(::RubyLLM::Providers::Anthropic) && provider.is_a?(::RubyLLM::Providers::Anthropic)
                    ::RubyLLM::Providers::Anthropic::Tools.tool_for(tool)
                  elsif tool.respond_to?(:params_schema) && tool.params_schema
                    build_basic_tool_schema(tool)
                  else
                    build_minimal_tool_schema(tool)
                  end
                rescue NameError, ArgumentError => e
                  # If provider-specific tool_for fails, fall back to basic format
                  Log.debug("Failed to extract tool schema using provider-specific method: #{e.class.name}: #{e.message}")
                  tool_schema = (tool.respond_to?(:params_schema) && tool.params_schema) ? build_basic_tool_schema(tool) : build_minimal_tool_schema(tool)
                end
              else
                # No provider, use basic format with params_schema if available
                tool_schema = (tool.respond_to?(:params_schema) && tool.params_schema) ? build_basic_tool_schema(tool) : build_minimal_tool_schema(tool)
              end

              # Strip RubyLLM-specific fields to match native OpenAI format
              # Handle both symbol and string keys
              function_key = tool_schema&.key?(:function) ? :function : "function"
              if tool_schema && tool_schema[function_key]
                tool_params = tool_schema[function_key][:parameters] || tool_schema[function_key]["parameters"]
                if tool_params.is_a?(Hash)
                  tool_params.delete("strict")
                  tool_params.delete(:strict)
                  tool_params.delete("additionalProperties")
                  tool_params.delete(:additionalProperties)
                end
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
            # Formats messages to match OpenAI's message format
            # @param chat [RubyLLM::Chat] the chat instance
            # @param prompt [String, nil] the user prompt
            # @return [Array<Hash>] array of message hashes
            def self.build_input_messages(chat, prompt)
              input_messages = []

              # Add conversation history, formatting each message to OpenAI format
              if chat.respond_to?(:messages) && chat.messages&.any?
                input_messages = chat.messages.map { |m| format_message_for_input(m) }
              end

              # Add current prompt
              input_messages << {"role" => "user", "content" => prompt} if prompt

              input_messages
            end

            # Format a RubyLLM message to OpenAI-compatible format
            # @param msg [Object] the RubyLLM message
            # @return [Hash] OpenAI-formatted message
            def self.format_message_for_input(msg)
              formatted = {
                "role" => msg.role.to_s
              }

              # Handle content
              if msg.respond_to?(:content) && msg.content
                # Convert Ruby hash notation to JSON string for tool results
                content = msg.content
                if msg.role.to_s == "tool" && content.is_a?(String) && content.start_with?("{:")
                  # Ruby hash string like "{:location=>...}" - try to parse and re-serialize as JSON
                  begin
                    # Simple conversion: replace Ruby hash syntax with JSON
                    content = content.gsub(/(?<=\{|, ):(\w+)=>/, '"\1":').gsub("=>", ":")
                  rescue
                    # Keep original if conversion fails
                  end
                end
                formatted["content"] = content
              end

              # Handle tool_calls for assistant messages
              if msg.respond_to?(:tool_calls) && msg.tool_calls&.any?
                formatted["tool_calls"] = format_tool_calls(msg.tool_calls)
                formatted["content"] = nil
              end

              # Handle tool_call_id for tool result messages
              if msg.respond_to?(:tool_call_id) && msg.tool_call_id
                formatted["tool_call_id"] = msg.tool_call_id
              end

              formatted
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
              # Look at messages added during this complete() call
              if chat.respond_to?(:messages) && chat.messages
                assistant_msg = chat.messages[messages_before_count..].find { |m|
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
    end
  end
end
