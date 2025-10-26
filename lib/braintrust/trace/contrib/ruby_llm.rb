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
      end

      # Parse usage tokens from RubyLLM message response
      # Maps ruby_llm field names to Braintrust standard names:
      # - input_tokens → prompt_tokens
      # - output_tokens → completion_tokens
      # - total → tokens (calculated)
      # - cached_tokens → prompt_cached_tokens
      # - cache_creation_tokens → prompt_cache_creation_tokens
      #
      # @param message [RubyLLM::Message] message object from RubyLLM response
      # @return [Hash<String, Integer>] metrics hash with normalized names
      def self.parse_usage_tokens(message)
        metrics = {}
        return metrics unless message

        # Map input_tokens to prompt_tokens
        if message.input_tokens
          metrics["prompt_tokens"] = message.input_tokens.to_i
        end

        # Map output_tokens to completion_tokens
        if message.output_tokens
          metrics["completion_tokens"] = message.output_tokens.to_i
        end

        # Calculate total tokens
        if metrics["prompt_tokens"] && metrics["completion_tokens"]
          metrics["tokens"] = metrics["prompt_tokens"] + metrics["completion_tokens"]
        end

        # Map cache-related tokens (Anthropic-specific)
        if message.respond_to?(:cached_tokens) && message.cached_tokens
          metrics["prompt_cached_tokens"] = message.cached_tokens.to_i
        end

        if message.respond_to?(:cache_creation_tokens) && message.cache_creation_tokens
          metrics["prompt_cache_creation_tokens"] = message.cache_creation_tokens.to_i
        end

        metrics
      end

      # Detect provider from chat instance
      # @param chat [RubyLLM::Chat] the chat instance
      # @return [String] provider name (e.g., "openai", "anthropic")
      def self.detect_provider(chat)
        # Access the @provider instance variable
        provider_obj = chat.instance_variable_get(:@provider)
        return "unknown" unless provider_obj

        # Get provider class name and extract the last part
        # e.g., "RubyLLM::Providers::OpenAI" -> "openai"
        provider_class = provider_obj.class.name
        provider_class.split("::").last.downcase
      rescue => e
        Log.warn("Failed to detect provider: #{e.message}")
        "unknown"
      end

      # Wrap a RubyLLM::Chat instance to automatically create spans for chat completions
      # Uses RubyLLM's event callbacks (on_new_message, on_end_message) to instrument requests
      #
      # @param chat [RubyLLM::Chat] the RubyLLM chat instance to wrap
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
      # @return [RubyLLM::Chat] the chat instance (for method chaining)
      def self.wrap(chat, tracer_provider: nil)
        tracer_provider ||= ::OpenTelemetry.tracer_provider

        # Store current span, tool span, tracer, and input messages in a closure
        current_span = nil
        last_finished_span = nil # Track the last finished span (for tool spans to use as parent)
        current_tool_span = nil # Track the most recent tool span (ruby_llm executes tools sequentially)
        input_messages_snapshot = nil
        span_start_time = nil # Track when the span should start (for accurate duration)
        tracer = tracer_provider.tracer("braintrust")

        # Register on_new_message callback to start span and capture input
        chat.on_new_message do
          # Capture input messages BEFORE the response is added
          # This ensures we don't include the assistant's response in the input
          # Format messages to match OpenAI/Anthropic format
          input_messages_snapshot = if chat.messages&.any?
            chat.messages.map do |msg|
              formatted = {role: msg.role.to_s}

              # Add content if present
              formatted[:content] = msg.content if msg.content

              # Add tool_calls if present (format as array like OpenAI)
              if msg.respond_to?(:tool_calls) && msg.tool_calls && msg.tool_calls.any?
                formatted[:tool_calls] = msg.tool_calls.map do |_id, tc|
                  {
                    id: tc.respond_to?(:id) ? tc.id : tc[:id],
                    type: "function",
                    function: {
                      name: tc.respond_to?(:name) ? tc.name : tc[:name],
                      arguments: (tc.respond_to?(:arguments) ? tc.arguments : tc[:arguments]).to_json
                    }
                  }
                end
              end

              # Add tool_call_id for tool messages
              if msg.respond_to?(:tool_call_id) && msg.tool_call_id
                formatted[:tool_call_id] = msg.tool_call_id
              end

              formatted
            end
          end

          # Capture the start time for the span (we'll create the span later in on_end_message)
          # This ensures we capture the full duration of the LLM call
          span_start_time = Time.now
          current_span = nil
        end

        # Register on_end_message callback to set attributes and finish span
        chat.on_end_message do |message|
          # Check if message is nil (indicates error)
          unless message
            next
          end

          # Skip tool messages - these are intermediate messages in the conversation
          # representing tool results being fed back to the LLM, not actual LLM responses
          if message.respond_to?(:role) && message.role.to_s == "tool"
            span_start_time = nil
            next
          end

          # Create span now that we know this is a real LLM response (not a tool message)
          # TODO: We should set start_timestamp here to capture accurate duration,
          # but there's currently an issue with the timestamp format that causes
          # "bignum too big" error. For now, we accept slightly inaccurate duration.
          current_span = tracer.start_span("ruby_llm.chat.ask")

          # Mark the span as an LLM call for Braintrust UI
          current_span.set_attribute("braintrust.span_attributes", JSON.generate({
            type: "llm",
            name: "ruby_llm.chat.ask"
          }))

          # Initialize metadata hash
          metadata = {
            "provider" => detect_provider(chat),
            "model" => message.model_id
          }

          # Add optional request parameters to metadata
          metadata["temperature"] = chat.instance_variable_get(:@temperature) if chat.instance_variable_get(:@temperature)

          # Capture custom params and headers if present
          params = chat.params
          metadata.merge!(params) if params && !params.empty?

          # Set input messages as JSON using the snapshot taken before response
          # This ensures we don't include the assistant's response in the input
          if input_messages_snapshot&.any?
            set_json_attr(current_span, "braintrust.input_json", input_messages_snapshot)
          end

          # Set output content as JSON
          # Format output as message array (consistent with OpenAI/Anthropic integrations)
          output_message = {role: "assistant"}

          # Add content if present
          output_message[:content] = message.content if message.content

          # Add tool_calls if present (following OpenAI format)
          if message.respond_to?(:tool_calls) && message.tool_calls && message.tool_calls.any?
            # RubyLLM returns tool_calls as a hash: {tool_call_id => ToolCall object}
            # Convert to OpenAI format array
            output_message[:tool_calls] = message.tool_calls.map do |_id, tc|
              {
                id: tc.respond_to?(:id) ? tc.id : tc[:id],
                type: "function",
                function: {
                  name: tc.respond_to?(:name) ? tc.name : tc[:name],
                  arguments: (tc.respond_to?(:arguments) ? tc.arguments : tc[:arguments]).to_json
                }
              }
            end
          end

          set_json_attr(current_span, "braintrust.output_json", [output_message])

          # Set metrics (token usage)
          metrics = parse_usage_tokens(message)
          set_json_attr(current_span, "braintrust.metrics", metrics) unless metrics.empty?

          # Set metadata
          set_json_attr(current_span, "braintrust.metadata", metadata)

          # Finish the span
          current_span.finish
          last_finished_span = current_span
        rescue => e
          # If an error occurs while setting attributes, still finish the span
          current_span&.record_exception(e)
          current_span&.status = ::OpenTelemetry::Trace::Status.error("Error processing span: #{e.message}")
          current_span&.finish
          last_finished_span = current_span
        ensure
          current_span = nil
          input_messages_snapshot = nil
          span_start_time = nil
        end

        # Register on_tool_call callback to create child spans for tool invocations
        chat.on_tool_call do |tool_call|
          # Use current_span if available, otherwise use last_finished_span
          # This handles the case where the parent span was finished before on_tool_call was triggered
          parent_span = current_span || last_finished_span
          next unless parent_span

          begin
            # tool_call is a RubyLLM::ToolCall object with id, name, and arguments attributes
            tool_name = tool_call.respond_to?(:name) ? tool_call.name : tool_call[:name]
            tool_id = tool_call.respond_to?(:id) ? tool_call.id : tool_call[:id]
            tool_arguments = tool_call.respond_to?(:arguments) ? tool_call.arguments : tool_call[:arguments]

            # Create a child span for the tool call
            # The span will be a child of the parent span (either current or last finished)
            tool_span = tracer.start_span(
              "tool: #{tool_name}",
              with_parent: OpenTelemetry::Trace.context_with_span(parent_span)
            )

            # Tag the span as a tool call
            # Set braintrust.span_attributes to control how Braintrust displays the span
            tool_span.set_attribute("braintrust.span_attributes", JSON.generate({
              type: "tool",
              name: "tool: #{tool_name}"
            }))
            tool_span.set_attribute("gen_ai.operation.name", "tool_call")

            # Store the span for later finishing (ruby_llm executes tools sequentially)
            current_tool_span = tool_span

            # Set input arguments as JSON
            if tool_arguments
              set_json_attr(tool_span, "braintrust.input_json", tool_arguments)
            end

            # Set metadata
            metadata = {
              "tool_name" => tool_name,
              "tool_id" => tool_id,
              "type" => "tool"
            }
            set_json_attr(tool_span, "braintrust.metadata", metadata)
          rescue => e
            Log.warn("Error creating tool call span: #{e.message}")
          end
        end

        # Register on_tool_result callback to finish tool spans
        chat.on_tool_result do |result|
          next unless result

          begin
            # Finish the current tool span
            # Ruby_LLM executes tools sequentially, so we finish the most recent one
            if current_tool_span
              # Set output result as JSON
              set_json_attr(current_tool_span, "braintrust.output_json", result)

              # Finish the tool span
              current_tool_span.finish

              # Clear the tracking
              current_tool_span = nil
            end
          rescue => e
            Log.warn("Error finishing tool result span: #{e.message}")
          end
        end

        chat
      end
    end
  end
end
