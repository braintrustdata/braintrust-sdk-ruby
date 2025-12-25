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
        # Responses API instrumentation for ruby-openai.
        # Provides module that can be prepended to OpenAI::Responses to instrument the create method.
        module Responses
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
            # Wrap create method for ruby-openai responses API
            # ruby-openai API: client.responses.create(parameters: {...})
            def create(parameters:)
              # Get tracer from client (context is set on client, not responses object)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)

              tracer.in_span("openai.responses.create") do |span|
                # Track start time for time_to_first_token
                start_time = Time.now
                time_to_first_token = nil
                is_streaming = parameters.key?(:stream) && parameters[:stream].is_a?(Proc)

                # Initialize metadata hash
                metadata = {
                  "provider" => "openai",
                  "endpoint" => "/v1/responses"
                }

                # Capture request metadata fields
                metadata_fields = %w[
                  model instructions modalities tools parallel_tool_calls
                  tool_choice temperature max_tokens top_p frequency_penalty
                  presence_penalty seed user metadata store response_format
                  reasoning previous_response_id truncation
                ]

                metadata_fields.each do |field|
                  field_sym = field.to_sym
                  metadata[field] = parameters[field_sym] if parameters.key?(field_sym)
                end

                # Mark as streaming if applicable
                metadata["stream"] = true if is_streaming

                # Set input as JSON
                if parameters[:input]
                  Support::OTel.set_json_attr(span, "braintrust.input_json", parameters[:input])
                end

                # Wrap streaming callback if present to capture time to first token and aggregate chunks
                aggregated_chunks = []
                if is_streaming
                  original_stream_proc = parameters[:stream]
                  parameters = parameters.dup
                  parameters[:stream] = proc do |chunk, event|
                    # Capture time to first token on first chunk
                    time_to_first_token ||= Time.now - start_time
                    # Aggregate chunks for later processing
                    aggregated_chunks << chunk
                    # Call original callback
                    original_stream_proc.call(chunk, event)
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
                    aggregated_response = Common.aggregate_responses_chunks(aggregated_chunks)

                    # Set output as JSON
                    if aggregated_response["output"]
                      Support::OTel.set_json_attr(span, "braintrust.output_json", aggregated_response["output"])
                    end

                    # Set metrics (token usage + time_to_first_token)
                    metrics = {}
                    if aggregated_response["usage"]
                      metrics = Support::OpenAI.parse_usage_tokens(aggregated_response["usage"])
                    end
                    metrics["time_to_first_token"] = time_to_first_token || 0.0
                    Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?

                    # Update metadata with response fields
                    metadata["id"] = aggregated_response["id"] if aggregated_response["id"]
                  else
                    # Non-streaming: use response hash directly
                    if response && response["output"]
                      Support::OTel.set_json_attr(span, "braintrust.output_json", response["output"])
                    end

                    # Set metrics (token usage + time_to_first_token)
                    metrics = {}
                    if response && response["usage"]
                      metrics = Support::OpenAI.parse_usage_tokens(response["usage"])
                    end
                    metrics["time_to_first_token"] = time_to_first_token || 0.0
                    Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?

                    # Update metadata with response fields
                    metadata["id"] = response["id"] if response && response["id"]
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
          end
        end
      end
    end
  end
end
