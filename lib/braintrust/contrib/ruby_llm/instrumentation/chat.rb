# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

require_relative "../../support/otel"
require_relative "../../support/anthropic"

module Braintrust
  module Contrib
    module RubyLLM
      module Instrumentation
        # Chat instrumentation for RubyLLM.
        # Wraps complete() and execute_tool() methods to create spans.
        module Chat
          def self.included(base)
            # Guard against double-wrapping
            base.prepend(InstanceMethods) unless applied?(base)
          end

          def self.applied?(base)
            base.ancestors.include?(InstanceMethods)
          end

          module InstanceMethods
            # Wrap complete() to trace chat completions.
            # Each call creates a span - recursive calls from tool execution
            # create nested spans (each is a separate API call).
            def complete(&block)
              return block ? super : super() unless tracing_enabled?

              tracer = Braintrust::Contrib.tracer_for(self)

              tracer.in_span("ruby_llm.chat") do |span|
                if block
                  # Streaming: pass a block that calls super() with the wrapper
                  handle_streaming_complete(span, block) do |&wrapper|
                    super(&wrapper)
                  end
                else
                  # Non-streaming: pass a block that calls super()
                  handle_non_streaming_complete(span) do
                    super()
                  end
                end
              end
            end

            private

            # Wrap execute_tool() to trace tool executions.
            # This is a private method in RubyLLM - wrapping it avoids
            # conflicting with user-registered on_tool_call/on_tool_result callbacks.
            def execute_tool(tool_call)
              return super unless tracing_enabled?

              tracer = Braintrust::Contrib.tracer_for(self)

              tracer.in_span("ruby_llm.tool.#{tool_call.name}") do |span|
                Support::OTel.set_json_attr(span, "braintrust.span_attributes", {type: "tool"})
                span.set_attribute("tool.name", tool_call.name)
                span.set_attribute("tool.call_id", tool_call.id)

                Support::OTel.set_json_attr(span, "braintrust.input_json", {
                  "name" => tool_call.name,
                  "arguments" => tool_call.arguments
                })

                result = super

                Support::OTel.set_json_attr(span, "braintrust.output_json", result)
                result
              end
            end

            # DEPRECATED: Support legacy unwrap()
            # Checks Context for enabled: false on instance or class.
            # This will be removed in a future version.
            def tracing_enabled?
              ctx = Braintrust::Contrib.context_for(self)
              class_ctx = Braintrust::Contrib.context_for(self.class)
              ctx&.[](:enabled) != false && class_ctx&.[](:enabled) != false
            end

            # Handle streaming complete request with tracing.
            # Calls the provided block with a wrapper that aggregates chunks.
            # @param span [OpenTelemetry::Trace::Span] the span to record to
            # @param user_block [Proc] the streaming block from user
            # @param super_caller [Proc] block that calls super(&wrapper)
            def handle_streaming_complete(span, user_block, &super_caller)
              aggregated_chunks = []
              metadata = extract_metadata(stream: true)
              input_messages = build_input_messages

              Support::OTel.set_json_attr(span, "braintrust.input_json", input_messages) if input_messages.any?
              Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)

              # Wrapper block that RubyLLM calls once per chunk.
              # Aggregates chunks for span recording and forwards to user's block.
              wrapper = proc do |chunk|
                aggregated_chunks << chunk
                user_block.call(chunk)
              end

              begin
                result = super_caller.call(&wrapper)

                capture_streaming_output(span, aggregated_chunks, result)
                result
              rescue => e
                span.record_exception(e)
                span.status = ::OpenTelemetry::Trace::Status.error("RubyLLM error: #{e.message}")
                raise
              end
            end

            # Handle non-streaming complete request with tracing.
            # Calls the provided block to invoke super() and returns the response.
            # @param span [OpenTelemetry::Trace::Span] the span to record to
            # @param super_caller [Proc] block that calls super()
            def handle_non_streaming_complete(span, &super_caller)
              metadata = extract_metadata
              input_messages = build_input_messages
              Support::OTel.set_json_attr(span, "braintrust.input_json", input_messages) if input_messages.any?

              messages_before_count = messages&.length || 0

              begin
                response = super_caller.call

                capture_non_streaming_output(span, response, messages_before_count)
                Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)

                response
              rescue => e
                span.record_exception(e)
                span.status = ::OpenTelemetry::Trace::Status.error("RubyLLM error: #{e.message}")
                raise
              end
            end

            # Extract metadata from chat instance (provider, model, tools, stream flag)
            def extract_metadata(stream: false)
              metadata = {"provider" => "ruby_llm"}
              metadata["stream"] = true if stream

              # Extract model
              if respond_to?(:model) && model
                model_id = model.respond_to?(:id) ? model.id : model.to_s
                metadata["model"] = model_id
              end

              # Extract tools (only for non-streaming)
              if !stream && respond_to?(:tools) && tools&.any?
                metadata["tools"] = extract_tools_metadata
              end

              metadata
            end

            # Extract tools metadata from chat instance
            def extract_tools_metadata
              provider = instance_variable_get(:@provider) if instance_variable_defined?(:@provider)

              tools.map do |_name, tool|
                format_tool_schema(tool, provider)
              end
            end

            # Format a tool into OpenAI-compatible schema
            def format_tool_schema(tool, provider)
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
                  Braintrust::Log.debug("Failed to extract tool schema using provider-specific method: #{e.class.name}: #{e.message}")
                  tool_schema = (tool.respond_to?(:params_schema) && tool.params_schema) ? build_basic_tool_schema(tool) : build_minimal_tool_schema(tool)
                end
              else
                tool_schema = (tool.respond_to?(:params_schema) && tool.params_schema) ? build_basic_tool_schema(tool) : build_minimal_tool_schema(tool)
              end

              # Strip RubyLLM-specific fields to match native OpenAI format
              function_key = tool_schema&.key?(:function) ? :function : "function"
              if tool_schema && tool_schema[function_key]
                tool_params = tool_schema[function_key][:parameters] || tool_schema[function_key]["parameters"]
                if tool_params.is_a?(Hash)
                  tool_params = tool_params.dup if tool_params.frozen?
                  tool_params.delete("strict")
                  tool_params.delete(:strict)
                  tool_params.delete("additionalProperties")
                  tool_params.delete(:additionalProperties)
                  params_key = tool_schema[function_key].key?(:parameters) ? :parameters : "parameters"
                  tool_schema[function_key][params_key] = tool_params
                end
              end

              tool_schema
            end

            # Build a basic tool schema with parameters
            def build_basic_tool_schema(tool)
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
            def build_minimal_tool_schema(tool)
              {
                "type" => "function",
                "function" => {
                  "name" => tool.name.to_s,
                  "description" => tool.description,
                  "parameters" => {}
                }
              }
            end

            # Build input messages array from chat history
            def build_input_messages
              return [] unless respond_to?(:messages) && messages&.any?

              messages.map { |m| format_message_for_input(m) }
            end

            # Format a RubyLLM message to OpenAI-compatible format
            def format_message_for_input(msg)
              formatted = {"role" => msg.role.to_s}

              # Handle content
              if msg.respond_to?(:content) && msg.content
                content = msg.content
                if msg.role.to_s == "tool" && content.is_a?(String) && content.start_with?("{:")
                  begin
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

            # Format tool calls into OpenAI format
            def format_tool_calls(tool_calls)
              tool_calls.map do |_id, tc|
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

            # Capture streaming output and metrics
            def capture_streaming_output(span, aggregated_chunks, result)
              return if aggregated_chunks.empty?

              aggregated_content = aggregated_chunks.map { |c|
                c.respond_to?(:content) ? c.content : c.to_s
              }.join

              output = [{
                role: "assistant",
                content: aggregated_content
              }]
              Support::OTel.set_json_attr(span, "braintrust.output_json", output)

              # Try to extract usage from the result
              if result.respond_to?(:usage) && result.usage
                metrics = Braintrust::Contrib::Support::Anthropic.parse_usage_tokens(result.usage)
                Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
              end
            end

            # Capture non-streaming output and metrics
            def capture_non_streaming_output(span, response, messages_before_count)
              return unless response

              message = {
                "role" => "assistant",
                "content" => nil
              }

              if response.respond_to?(:content) && response.content && !response.content.empty?
                message["content"] = response.content
              end

              # Check if there are tool calls in the messages history
              if respond_to?(:messages) && messages
                assistant_msg = messages[messages_before_count..]&.find { |m|
                  m.role.to_s == "assistant" && m.respond_to?(:tool_calls) && m.tool_calls&.any?
                }

                if assistant_msg&.tool_calls&.any?
                  message["tool_calls"] = format_tool_calls(assistant_msg.tool_calls)
                  message["content"] = nil
                end
              end

              output = [{
                "index" => 0,
                "message" => message,
                "finish_reason" => message["tool_calls"] ? "tool_calls" : "stop"
              }]

              Support::OTel.set_json_attr(span, "braintrust.output_json", output)

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
                  metrics = Braintrust::Contrib::Support::Anthropic.parse_usage_tokens(usage)
                  Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
                end
              end
            end
          end
        end
      end
    end
  end
end
