# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

module Braintrust
  module Trace
    module OpenAI
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

      # Parse usage tokens from OpenAI API response, handling nested token_details
      # Maps OpenAI field names to Braintrust standard names:
      # - input_tokens → prompt_tokens
      # - output_tokens → completion_tokens
      # - total_tokens → tokens
      # - *_tokens_details.* → prefix_*
      #
      # @param usage [Hash, Object] usage object from OpenAI response
      # @return [Hash<String, Integer>] metrics hash with normalized names
      def self.parse_usage_tokens(usage)
        metrics = {}
        return metrics unless usage

        # Convert to hash if it's an object
        usage_hash = usage.respond_to?(:to_h) ? usage.to_h : usage

        usage_hash.each do |key, value|
          key_str = key.to_s

          # Handle nested *_tokens_details objects
          if key_str.end_with?("_tokens_details")
            # Convert to hash if it's an object (OpenAI gem returns objects)
            details_hash = value.respond_to?(:to_h) ? value.to_h : value
            next unless details_hash.is_a?(Hash)

            # Extract prefix (e.g., "prompt" from "prompt_tokens_details")
            prefix = key_str.sub(/_tokens_details$/, "")
            # Translate "input" → "prompt", "output" → "completion"
            prefix = translate_metric_prefix(prefix)

            # Process nested fields (e.g., cached_tokens, reasoning_tokens)
            details_hash.each do |detail_key, detail_value|
              next unless detail_value.is_a?(Numeric)
              metrics["#{prefix}_#{detail_key}"] = detail_value.to_i
            end
          elsif value.is_a?(Numeric)
            # Handle top-level token fields
            case key_str
            when "input_tokens"
              metrics["prompt_tokens"] = value.to_i
            when "output_tokens"
              metrics["completion_tokens"] = value.to_i
            when "total_tokens"
              metrics["tokens"] = value.to_i
            else
              # Keep other numeric fields as-is (future-proofing)
              metrics[key_str] = value.to_i
            end
          end
        end

        metrics
      end

      # Translate metric prefix to be consistent between different API formats
      # @param prefix [String] the prefix to translate
      # @return [String] translated prefix
      def self.translate_metric_prefix(prefix)
        case prefix
        when "input"
          "prompt"
        when "output"
          "completion"
        else
          prefix
        end
      end

      # Aggregate streaming chunks into a single response structure
      # Follows the Go SDK logic for aggregating deltas
      # @param chunks [Array<Hash>] array of chunk hashes from stream
      # @return [Hash] aggregated response with choices, usage, etc.
      def self.aggregate_streaming_chunks(chunks)
        return {} if chunks.empty?

        # Initialize aggregated structure
        aggregated = {
          id: nil,
          created: nil,
          model: nil,
          system_fingerprint: nil,
          choices: [],
          usage: nil
        }

        # Track aggregated content and tool_calls for each choice index
        choice_data = {}

        chunks.each do |chunk|
          # Capture top-level fields from any chunk that has them
          aggregated[:id] ||= chunk[:id]
          aggregated[:created] ||= chunk[:created]
          aggregated[:model] ||= chunk[:model]
          aggregated[:system_fingerprint] ||= chunk[:system_fingerprint]

          # Aggregate usage (usually only in last chunk if stream_options.include_usage is set)
          if chunk[:usage]
            aggregated[:usage] = chunk[:usage]
          end

          # Process choices
          next unless chunk[:choices].is_a?(Array)
          chunk[:choices].each do |choice|
            index = choice[:index] || 0
            choice_data[index] ||= {
              index: index,
              role: nil,
              content: "",
              tool_calls: [],
              finish_reason: nil
            }

            delta = choice[:delta] || {}

            # Aggregate role (set once from first delta that has it)
            choice_data[index][:role] ||= delta[:role]

            # Aggregate content
            if delta[:content]
              choice_data[index][:content] += delta[:content]
            end

            # Aggregate tool_calls (similar to Go SDK logic)
            if delta[:tool_calls].is_a?(Array) && delta[:tool_calls].any?
              delta[:tool_calls].each do |tool_call_delta|
                # Check if this is a new tool call or continuation
                if tool_call_delta[:id] && !tool_call_delta[:id].empty?
                  # New tool call
                  choice_data[index][:tool_calls] << {
                    id: tool_call_delta[:id],
                    type: tool_call_delta[:type],
                    function: {
                      name: tool_call_delta.dig(:function, :name) || "",
                      arguments: tool_call_delta.dig(:function, :arguments) || ""
                    }
                  }
                elsif choice_data[index][:tool_calls].any?
                  # Continuation - append arguments to last tool call
                  last_tool_call = choice_data[index][:tool_calls].last
                  if tool_call_delta.dig(:function, :arguments)
                    last_tool_call[:function][:arguments] += tool_call_delta[:function][:arguments]
                  end
                end
              end
            end

            # Capture finish_reason
            if choice[:finish_reason]
              choice_data[index][:finish_reason] = choice[:finish_reason]
            end
          end
        end

        # Build final choices array
        aggregated[:choices] = choice_data.values.sort_by { |c| c[:index] }.map do |choice|
          message = {
            role: choice[:role],
            content: choice[:content].empty? ? nil : choice[:content]
          }

          # Add tool_calls to message if any
          message[:tool_calls] = choice[:tool_calls] if choice[:tool_calls].any?

          {
            index: choice[:index],
            message: message,
            finish_reason: choice[:finish_reason]
          }
        end

        aggregated
      end

      # Wrap an OpenAI::Client to automatically create spans for chat completions
      # Supports both synchronous and streaming requests
      # @param client [OpenAI::Client] the OpenAI client to wrap
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
      def self.wrap(client, tracer_provider: nil)
        tracer_provider ||= ::OpenTelemetry.tracer_provider

        # Create a wrapper module that intercepts chat.completions.create
        wrapper = Module.new do
          define_method(:create) do |**params|
            tracer = tracer_provider.tracer("braintrust")

            tracer.in_span("openai.chat.completions.create") do |span|
              # Initialize metadata hash
              metadata = {
                "provider" => "openai",
                "endpoint" => "/v1/chat/completions"
              }

              # Capture request metadata fields
              metadata_fields = %i[
                model frequency_penalty logit_bias logprobs max_tokens n
                presence_penalty response_format seed service_tier stop
                stream stream_options temperature top_p top_logprobs
                tools tool_choice parallel_tool_calls user functions function_call
              ]

              metadata_fields.each do |field|
                metadata[field.to_s] = params[field] if params.key?(field)
              end

              # Set input messages as JSON
              # Pass through all message fields to preserve tool_calls, tool_call_id, name, etc.
              if params[:messages]
                messages_array = params[:messages].map(&:to_h)
                span.set_attribute("braintrust.input_json", JSON.generate(messages_array))
              end

              # Call the original method
              response = super(**params)

              # Set output (choices) as JSON
              # Use to_h to get the raw structure with all fields (including tool_calls)
              if response.respond_to?(:choices) && response.choices&.any?
                choices_array = response.choices.map(&:to_h)
                span.set_attribute("braintrust.output_json", JSON.generate(choices_array))
              end

              # Set metrics (token usage with advanced details)
              if response.respond_to?(:usage) && response.usage
                metrics = Braintrust::Trace::OpenAI.parse_usage_tokens(response.usage)
                span.set_attribute("braintrust.metrics", JSON.generate(metrics)) unless metrics.empty?
              end

              # Add response metadata fields
              metadata["id"] = response.id if response.respond_to?(:id) && response.id
              metadata["created"] = response.created if response.respond_to?(:created) && response.created
              metadata["system_fingerprint"] = response.system_fingerprint if response.respond_to?(:system_fingerprint) && response.system_fingerprint
              metadata["service_tier"] = response.service_tier if response.respond_to?(:service_tier) && response.service_tier

              # Set metadata ONCE at the end with complete hash
              span.set_attribute("braintrust.metadata", JSON.generate(metadata))

              response
            end
          end

          # Wrap stream_raw for streaming chat completions
          define_method(:stream_raw) do |**params|
            tracer = tracer_provider.tracer("braintrust")
            aggregated_chunks = []
            metadata = {
              "provider" => "openai",
              "endpoint" => "/v1/chat/completions"
            }

            # Start span with proper context (will be child of current span if any)
            span = tracer.start_span("openai.chat.completions.create")

            # Capture request metadata fields
            metadata_fields = %i[
              model frequency_penalty logit_bias logprobs max_tokens n
              presence_penalty response_format seed service_tier stop
              stream stream_options temperature top_p top_logprobs
              tools tool_choice parallel_tool_calls user functions function_call
            ]

            metadata_fields.each do |field|
              metadata[field.to_s] = params[field] if params.key?(field)
            end
            metadata["stream"] = true  # Explicitly mark as streaming

            # Set input messages as JSON
            if params[:messages]
              messages_array = params[:messages].map(&:to_h)
              span.set_attribute("braintrust.input_json", JSON.generate(messages_array))
            end

            # Set initial metadata
            span.set_attribute("braintrust.metadata", JSON.generate(metadata))

            # Call the original stream_raw method with error handling
            begin
              stream = super(**params)
            rescue => e
              # Record exception if stream creation fails
              span.record_exception(e)
              span.status = ::OpenTelemetry::Trace::Status.error("OpenAI API error: #{e.message}")
              span.finish
              raise
            end

            # Wrap the stream to aggregate chunks
            original_each = stream.method(:each)
            stream.define_singleton_method(:each) do |&block|
              original_each.call do |chunk|
                aggregated_chunks << chunk.to_h
                block&.call(chunk)
              end
            rescue => e
              # Record exception if streaming fails
              span.record_exception(e)
              span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
              raise
            ensure
              # Always aggregate whatever chunks we collected and finish span
              # This runs on normal completion, break, or exception
              unless aggregated_chunks.empty?
                aggregated_output = Braintrust::Trace::OpenAI.aggregate_streaming_chunks(aggregated_chunks)
                Braintrust::Trace::OpenAI.set_json_attr(span, "braintrust.output_json", aggregated_output[:choices])

                # Set metrics if usage is included (requires stream_options.include_usage)
                if aggregated_output[:usage]
                  metrics = Braintrust::Trace::OpenAI.parse_usage_tokens(aggregated_output[:usage])
                  Braintrust::Trace::OpenAI.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
                end

                # Update metadata with response fields
                metadata["id"] = aggregated_output[:id] if aggregated_output[:id]
                metadata["created"] = aggregated_output[:created] if aggregated_output[:created]
                metadata["model"] = aggregated_output[:model] if aggregated_output[:model]
                metadata["system_fingerprint"] = aggregated_output[:system_fingerprint] if aggregated_output[:system_fingerprint]
                Braintrust::Trace::OpenAI.set_json_attr(span, "braintrust.metadata", metadata)
              end

              span.finish
            end

            stream
          end
        end

        # Prepend the wrapper to the completions resource
        client.chat.completions.singleton_class.prepend(wrapper)

        client
      end
    end
  end
end
