# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

require_relative "common"
require_relative "../../support/otel"
require_relative "../../support/openai"

module Braintrust
  module Contrib
    module RubyOpenAI
      module Instrumentation
        # Chat completions instrumentation for ruby-openai.
        # Provides module that can be prepended to OpenAI::Client to instrument the chat method.
        module Chat
          def self.included(base)
            # Guard against double-wrapping: Check if patch is already in the ancestor chain.
            # This prevents double instrumentation if class-level patching was already applied,
            # and this patch is being applied to a singleton-class. (Special case.)
            #
            # Ruby's prepend() doesn't check the full inheritance chain, so without this guard,
            # the instrumentation could be added twice.
            base.prepend(InstanceMethods) unless applied?(base)
          end

          def self.applied?(base)
            base.ancestors.include?(InstanceMethods)
          end

          module InstanceMethods
            # Wrap chat method for ruby-openai gem
            # ruby-openai API: client.chat(parameters: {...})
            def chat(parameters:)
              tracer = Braintrust::Contrib.tracer_for(self)

              tracer.in_span("Chat Completion") do |span|
                # Track start time for time_to_first_token
                start_time = Time.now
                time_to_first_token = nil
                is_streaming = parameters.key?(:stream) && parameters[:stream].is_a?(Proc)

                # Initialize metadata hash
                metadata = {
                  "provider" => "openai",
                  "endpoint" => "/v1/chat/completions"
                }

                # Capture request metadata fields
                metadata_fields = %w[
                  model frequency_penalty logit_bias logprobs max_tokens n
                  presence_penalty response_format seed service_tier stop
                  stream stream_options temperature top_p top_logprobs
                  tools tool_choice parallel_tool_calls user functions function_call
                ]

                metadata_fields.each do |field|
                  field_sym = field.to_sym
                  if parameters.key?(field_sym)
                    # Special handling for stream parameter (it's a Proc)
                    metadata[field] = if field == "stream"
                      true # Just mark as streaming
                    else
                      parameters[field_sym]
                    end
                  end
                end

                # Set input messages as JSON
                if parameters[:messages]
                  Support::OTel.set_json_attr(span, "braintrust.input_json", parameters[:messages])
                end

                # Wrap streaming callback if present to capture time to first token and aggregate chunks
                aggregated_chunks = []
                if is_streaming
                  original_stream_proc = parameters[:stream]
                  parameters = parameters.dup
                  parameters[:stream] = proc do |chunk, bytesize|
                    # Capture time to first token on first chunk
                    time_to_first_token ||= Time.now - start_time
                    # Aggregate chunks for later processing
                    aggregated_chunks << chunk
                    # Call original callback
                    original_stream_proc.call(chunk, bytesize)
                  end
                end

                begin
                  # Call the original method
                  response = super(parameters: parameters)

                  # Calculate time to first token for non-streaming
                  time_to_first_token ||= Time.now - start_time unless is_streaming

                  # Process response data
                  if is_streaming && !aggregated_chunks.empty?
                    # Aggregate streaming chunks into response-like structure
                    aggregated_response = Common.aggregate_streaming_chunks(aggregated_chunks)
                    set_span_attributes(span, aggregated_response, time_to_first_token, metadata)
                  else
                    # Non-streaming: use response hash directly
                    # ruby-openai returns raw Hash with string keys
                    set_span_attributes(span, response || {}, time_to_first_token, metadata)
                  end

                  # Set metadata ONCE at the end with complete hash
                  Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)

                  response
                rescue => e
                  # Record exception in span
                  span.record_exception(e)
                  span.status = ::OpenTelemetry::Trace::Status.error("Exception: #{e.class} - #{e.message}")
                  raise
                end
              end
            end

            private

            # Set span attributes from response data (works for both streaming and non-streaming)
            # @param span [OpenTelemetry::Trace::Span] the span to set attributes on
            # @param response_data [Hash] response hash (string or symbol keys)
            # @param time_to_first_token [Float] time to first token in seconds
            # @param metadata [Hash] metadata hash to update with response fields
            def set_span_attributes(span, response_data, time_to_first_token, metadata)
              # Handle both string and symbol keys
              choices = response_data[:choices] || response_data["choices"]
              usage = response_data[:usage] || response_data["usage"]

              # Set output (choices) as JSON
              if choices&.any?
                Support::OTel.set_json_attr(span, "braintrust.output_json", choices)
              end

              # Set metrics (token usage + time_to_first_token)
              metrics = {}
              if usage
                metrics = Support::OpenAI.parse_usage_tokens(usage)
              end
              metrics["time_to_first_token"] = time_to_first_token || 0.0
              Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?

              # Update metadata with response fields (handle both string and symbol keys)
              %w[id created model system_fingerprint service_tier].each do |field|
                value = response_data[field.to_sym] || response_data[field]
                metadata[field] = value if value
              end
            end
          end
        end
      end
    end
  end
end
