# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

require_relative "common"
require_relative "../../support/otel"
require_relative "../../support/openai"
require_relative "../../../internal/time"

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

          METADATA_FIELDS = %i[
            model instructions modalities tools parallel_tool_calls
            tool_choice temperature max_tokens top_p frequency_penalty
            presence_penalty seed user metadata store response_format
            reasoning previous_response_id truncation
          ].freeze

          module InstanceMethods
            # Wrap create method for ruby-openai responses API
            # ruby-openai API: client.responses.create(parameters: {...})
            def create(parameters:)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)

              tracer.in_span("openai.responses.create") do |span|
                is_streaming = streaming?(parameters)
                metadata = build_metadata(parameters)
                set_input(span, parameters)

                aggregated_chunks = []
                time_to_first_token = nil
                response = nil
                response_data = {}

                if is_streaming
                  # Setup a time measurement for the first chunk from the stream
                  start_time = nil
                  parameters = wrap_stream_callback(parameters, aggregated_chunks) do
                    time_to_first_token ||= Braintrust::Internal::Time.measure(start_time)
                  end
                  start_time = Braintrust::Internal::Time.measure

                  # Then initiate the stream
                  response = super(parameters: parameters)

                  if !aggregated_chunks.empty?
                    response_data = Common.aggregate_responses_chunks(aggregated_chunks)
                  end
                else
                  # Make a time measurement synchronously around the API call
                  time_to_first_token = Braintrust::Internal::Time.measure do
                    response = super(parameters: parameters)
                    response_data = response if response
                  end
                end

                set_output(span, response_data)
                set_metrics(span, response_data, time_to_first_token)
                finalize_metadata(span, metadata, response_data)

                response
              end
            end

            private

            def streaming?(parameters)
              parameters.key?(:stream) && parameters[:stream].is_a?(Proc)
            end

            def wrap_stream_callback(parameters, aggregated_chunks)
              original_stream_proc = parameters[:stream]
              parameters = parameters.dup

              parameters[:stream] = proc do |chunk, event|
                yield if aggregated_chunks.empty?
                aggregated_chunks << chunk
                original_stream_proc.call(chunk, event)
              end

              parameters
            end

            def build_metadata(parameters)
              metadata = {
                "provider" => "openai",
                "endpoint" => "/v1/responses"
              }

              Responses::METADATA_FIELDS.each do |field|
                metadata[field.to_s] = parameters[field] if parameters.key?(field)
              end

              metadata["stream"] = true if streaming?(parameters)
              metadata
            end

            def set_input(span, parameters)
              return unless parameters[:input]
              Support::OTel.set_json_attr(span, "braintrust.input_json", parameters[:input])
            end

            def set_output(span, response_data)
              output = response_data["output"]
              return unless output
              Support::OTel.set_json_attr(span, "braintrust.output_json", output)
            end

            def set_metrics(span, response_data, time_to_first_token)
              usage = response_data["usage"]
              metrics = usage ? Support::OpenAI.parse_usage_tokens(usage) : {}
              metrics["time_to_first_token"] = time_to_first_token || 0.0
              Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
            end

            def finalize_metadata(span, metadata, response_data)
              metadata["id"] = response_data["id"] if response_data["id"]
              Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)
            end
          end
        end
      end
    end
  end
end
