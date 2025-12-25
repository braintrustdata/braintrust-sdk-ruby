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

          METADATA_FIELDS = %i[
            model frequency_penalty logit_bias logprobs max_tokens n
            presence_penalty response_format seed service_tier stop
            stream stream_options temperature top_p top_logprobs
            tools tool_choice parallel_tool_calls user functions function_call
          ].freeze

          module InstanceMethods
            # Wrap chat method for ruby-openai gem
            # ruby-openai API: client.chat(parameters: {...})
            def chat(parameters:)
              tracer = Braintrust::Contrib.tracer_for(self)

              tracer.in_span("Chat Completion") do |span|
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
                    response_data = Common.aggregate_streaming_chunks(aggregated_chunks)
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

              parameters[:stream] = proc do |chunk, bytesize|
                yield if aggregated_chunks.empty?
                aggregated_chunks << chunk
                original_stream_proc.call(chunk, bytesize)
              end

              parameters
            end

            def build_metadata(parameters)
              metadata = {
                "provider" => "openai",
                "endpoint" => "/v1/chat/completions"
              }

              Chat::METADATA_FIELDS.each do |field|
                next unless parameters.key?(field)
                # Stream param is a Proc - just mark as true
                metadata[field.to_s] = (field == :stream) ? true : parameters[field]
              end

              metadata
            end

            def set_input(span, parameters)
              return unless parameters[:messages]
              Support::OTel.set_json_attr(span, "braintrust.input_json", parameters[:messages])
            end

            def set_output(span, response_data)
              choices = response_data[:choices] || response_data["choices"]
              return unless choices&.any?
              Support::OTel.set_json_attr(span, "braintrust.output_json", choices)
            end

            def set_metrics(span, response_data, time_to_first_token)
              usage = response_data[:usage] || response_data["usage"]
              metrics = usage ? Support::OpenAI.parse_usage_tokens(usage) : {}
              metrics["time_to_first_token"] = time_to_first_token || 0.0
              Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
            end

            def finalize_metadata(span, metadata, response_data)
              %w[id created model system_fingerprint service_tier].each do |field|
                value = response_data[field.to_sym] || response_data[field]
                metadata[field] = value if value
              end
              Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)
            end
          end
        end
      end
    end
  end
end
