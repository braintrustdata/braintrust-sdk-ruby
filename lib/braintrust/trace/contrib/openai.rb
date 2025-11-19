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
              content: +"",
              tool_calls: [],
              finish_reason: nil
            }

            delta = choice[:delta] || {}

            # Aggregate role (set once from first delta that has it)
            choice_data[index][:role] ||= delta[:role]

            # Aggregate content
            if delta[:content]
              choice_data[index][:content] << delta[:content]
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
                      name: tool_call_delta.dig(:function, :name) || +"",
                      arguments: tool_call_delta.dig(:function, :arguments) || +""
                    }
                  }
                elsif choice_data[index][:tool_calls].any?
                  # Continuation - append arguments to last tool call
                  last_tool_call = choice_data[index][:tool_calls].last
                  if tool_call_delta.dig(:function, :arguments)
                    last_tool_call[:function][:arguments] << tool_call_delta[:function][:arguments]
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

      # Wrap an OpenAI::Client to automatically create spans for chat completions and responses
      # Supports both synchronous and streaming requests
      # @param client [OpenAI::Client] the OpenAI client to wrap
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
      def self.wrap(client, tracer_provider: nil)
        tracer_provider ||= ::OpenTelemetry.tracer_provider

        # Wrap chat completions
        wrap_chat_completions(client, tracer_provider)

        # Wrap responses API if available
        wrap_responses(client, tracer_provider) if client.respond_to?(:responses)

        client
      end

      # Wrap chat completions API
      # @param client [OpenAI::Client] the OpenAI client
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
      def self.wrap_chat_completions(client, tracer_provider)
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

          # Wrap stream for streaming chat completions (returns ChatCompletionStream with convenience methods)
          define_method(:stream) do |**params|
            tracer = tracer_provider.tracer("braintrust")
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

            # Call the original stream method with error handling
            begin
              stream = super(**params)
            rescue => e
              # Record exception if stream creation fails
              span.record_exception(e)
              span.status = ::OpenTelemetry::Trace::Status.error("OpenAI API error: #{e.message}")
              span.finish
              raise
            end

            # Local helper for setting JSON attributes
            set_json_attr = ->(attr_name, obj) { Braintrust::Trace::OpenAI.set_json_attr(span, attr_name, obj) }

            # Helper to extract metadata from SDK's internal snapshot
            extract_stream_metadata = lambda do
              # Access the SDK's internal accumulated completion snapshot
              snapshot = stream.current_completion_snapshot
              return unless snapshot

              # Set output from accumulated choices
              if snapshot.choices&.any?
                choices_array = snapshot.choices.map(&:to_h)
                set_json_attr.call("braintrust.output_json", choices_array)
              end

              # Set metrics if usage is available
              if snapshot.usage
                metrics = Braintrust::Trace::OpenAI.parse_usage_tokens(snapshot.usage)
                set_json_attr.call("braintrust.metrics", metrics) unless metrics.empty?
              end

              # Update metadata with response fields
              metadata["id"] = snapshot.id if snapshot.respond_to?(:id) && snapshot.id
              metadata["created"] = snapshot.created if snapshot.respond_to?(:created) && snapshot.created
              metadata["model"] = snapshot.model if snapshot.respond_to?(:model) && snapshot.model
              metadata["system_fingerprint"] = snapshot.system_fingerprint if snapshot.respond_to?(:system_fingerprint) && snapshot.system_fingerprint
              set_json_attr.call("braintrust.metadata", metadata)
            end

            # Prevent double-finish of span
            finish_braintrust_span = lambda do
              return if stream.instance_variable_get(:@braintrust_span_finished)
              stream.instance_variable_set(:@braintrust_span_finished, true)
              extract_stream_metadata.call
              span.finish
            end

            # Wrap .each() method - this is the core consumption method
            original_each = stream.method(:each)
            stream.define_singleton_method(:each) do |&block|
              original_each.call(&block)
            rescue => e
              span.record_exception(e)
              span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
              raise
            ensure
              finish_braintrust_span.call
            end

            # Wrap .text() method - returns enumerable for text deltas
            original_text = stream.method(:text)
            stream.define_singleton_method(:text) do
              text_enum = original_text.call
              # Wrap the returned enumerable's .each method
              text_enum.define_singleton_method(:each) do |&block|
                super(&block)
              rescue => e
                span.record_exception(e)
                span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
                raise
              ensure
                finish_braintrust_span.call
              end
              text_enum
            end

            stream
          end
        end

        # Prepend the wrapper to the completions resource
        client.chat.completions.singleton_class.prepend(wrapper)
      end

      # Wrap responses API
      # @param client [OpenAI::Client] the OpenAI client
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
      def self.wrap_responses(client, tracer_provider)
        # Create a wrapper module that intercepts responses.create and responses.stream
        wrapper = Module.new do
          # Wrap non-streaming create method
          define_method(:create) do |**params|
            tracer = tracer_provider.tracer("braintrust")

            tracer.in_span("openai.responses.create") do |span|
              # Initialize metadata hash
              metadata = {
                "provider" => "openai",
                "endpoint" => "/v1/responses"
              }

              # Capture request metadata fields
              metadata_fields = %i[
                model instructions modalities tools parallel_tool_calls
                tool_choice temperature max_tokens top_p frequency_penalty
                presence_penalty seed user metadata store response_format
              ]

              metadata_fields.each do |field|
                metadata[field.to_s] = params[field] if params.key?(field)
              end

              # Set input as JSON
              if params[:input]
                span.set_attribute("braintrust.input_json", JSON.generate(params[:input]))
              end

              # Call the original method
              response = super(**params)

              # Set output as JSON
              if response.respond_to?(:output) && response.output
                span.set_attribute("braintrust.output_json", JSON.generate(response.output))
              end

              # Set metrics (token usage)
              if response.respond_to?(:usage) && response.usage
                metrics = Braintrust::Trace::OpenAI.parse_usage_tokens(response.usage)
                span.set_attribute("braintrust.metrics", JSON.generate(metrics)) unless metrics.empty?
              end

              # Add response metadata fields
              metadata["id"] = response.id if response.respond_to?(:id) && response.id

              # Set metadata ONCE at the end with complete hash
              span.set_attribute("braintrust.metadata", JSON.generate(metadata))

              response
            end
          end

          # Wrap streaming method
          define_method(:stream) do |**params|
            tracer = tracer_provider.tracer("braintrust")
            aggregated_events = []
            metadata = {
              "provider" => "openai",
              "endpoint" => "/v1/responses",
              "stream" => true
            }

            # Start span with proper context
            span = tracer.start_span("openai.responses.create")

            # Capture request metadata fields
            metadata_fields = %i[
              model instructions modalities tools parallel_tool_calls
              tool_choice temperature max_tokens top_p frequency_penalty
              presence_penalty seed user metadata store response_format
            ]

            metadata_fields.each do |field|
              metadata[field.to_s] = params[field] if params.key?(field)
            end

            # Set input as JSON
            if params[:input]
              span.set_attribute("braintrust.input_json", JSON.generate(params[:input]))
            end

            # Set initial metadata
            span.set_attribute("braintrust.metadata", JSON.generate(metadata))

            # Call the original stream method with error handling
            begin
              stream = super(**params)
            rescue => e
              # Record exception if stream creation fails
              span.record_exception(e)
              span.status = ::OpenTelemetry::Trace::Status.error("OpenAI API error: #{e.message}")
              span.finish
              raise
            end

            # Wrap the stream to aggregate events
            original_each = stream.method(:each)
            stream.define_singleton_method(:each) do |&block|
              original_each.call do |event|
                # Store the actual event object (not converted to hash)
                aggregated_events << event
                block&.call(event)
              end
            rescue => e
              # Record exception if streaming fails
              span.record_exception(e)
              span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
              raise
            ensure
              # Always aggregate whatever events we collected and finish span
              unless aggregated_events.empty?
                aggregated_output = Braintrust::Trace::OpenAI.aggregate_responses_events(aggregated_events)
                Braintrust::Trace::OpenAI.set_json_attr(span, "braintrust.output_json", aggregated_output[:output]) if aggregated_output[:output]

                # Set metrics if usage is included
                if aggregated_output[:usage]
                  metrics = Braintrust::Trace::OpenAI.parse_usage_tokens(aggregated_output[:usage])
                  Braintrust::Trace::OpenAI.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
                end

                # Update metadata with response fields
                metadata["id"] = aggregated_output[:id] if aggregated_output[:id]
                Braintrust::Trace::OpenAI.set_json_attr(span, "braintrust.metadata", metadata)
              end

              span.finish
            end

            stream
          end
        end

        # Prepend the wrapper to the responses resource
        client.responses.singleton_class.prepend(wrapper)
      end

      # Aggregate responses streaming events into a single response structure
      # Follows similar logic to Python SDK's _postprocess_streaming_results
      # @param events [Array] array of event objects from stream
      # @return [Hash] aggregated response with output, usage, etc.
      def self.aggregate_responses_events(events)
        return {} if events.empty?

        # Find the response.completed event which has the final response
        completed_event = events.find { |e| e.respond_to?(:type) && e.type == :"response.completed" }

        if completed_event&.respond_to?(:response)
          response = completed_event.response
          # Convert the response object to a hash-like structure for logging
          return {
            id: response.respond_to?(:id) ? response.id : nil,
            output: response.respond_to?(:output) ? response.output : nil,
            usage: response.respond_to?(:usage) ? response.usage : nil
          }
        end

        # Fallback if no completed event found
        {}
      end
    end
  end
end
