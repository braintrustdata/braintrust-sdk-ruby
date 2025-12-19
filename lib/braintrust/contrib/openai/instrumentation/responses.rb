# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

require_relative "common"
require_relative "../../../internal/time"

module Braintrust
  module Contrib
    module OpenAI
      module Instrumentation
        # Responses API instrumentation for OpenAI.
        # Wraps create() and stream() methods to create spans.
        module Responses
          def self.included(base)
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
            # Wrap non-streaming create method
            def create(**params)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)

              tracer.in_span("openai.responses.create") do |span|
                metadata = build_metadata(params)

                set_input(span, params)

                response = nil
                time_to_first_token = Braintrust::Internal::Time.measure do
                  response = super
                end

                set_output(span, response)
                set_metrics(span, response, time_to_first_token)
                finalize_metadata(span, metadata, response)

                response
              end
            end

            # Wrap streaming method
            # Stores context on stream object for span creation during consumption
            def stream(**params)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)
              metadata = build_metadata(params, stream: true)

              stream_obj = super

              Braintrust::Contrib::Context.set!(stream_obj,
                tracer: tracer,
                params: params,
                metadata: metadata,
                responses_instance: self)
              stream_obj
            end

            private

            def build_metadata(params, stream: false)
              metadata = {
                "provider" => "openai",
                "endpoint" => "/v1/responses"
              }
              metadata["stream"] = true if stream
              Responses::METADATA_FIELDS.each do |field|
                metadata[field.to_s] = params[field] if params.key?(field)
              end
              metadata
            end

            def set_input(span, params)
              return unless params[:input]

              Common.set_json_attr(span, "braintrust.input_json", params[:input])
            end

            def set_output(span, response)
              return unless response.respond_to?(:output) && response.output

              Common.set_json_attr(span, "braintrust.output_json", response.output)
            end

            def set_metrics(span, response, time_to_first_token)
              metrics = {}
              if response.respond_to?(:usage) && response.usage
                metrics = Common.parse_usage_tokens(response.usage)
              end
              metrics["time_to_first_token"] = time_to_first_token
              Common.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
            end

            def finalize_metadata(span, metadata, response)
              metadata["id"] = response.id if response.respond_to?(:id) && response.id
              Common.set_json_attr(span, "braintrust.metadata", metadata)
            end
          end
        end

        # Instrumentation for ResponseStream (returned by stream())
        # Aggregates events and creates span lazily when consumed
        module ResponseStream
          def self.included(base)
            base.prepend(InstanceMethods) unless applied?(base)
          end

          def self.applied?(base)
            base.ancestors.include?(InstanceMethods)
          end

          module InstanceMethods
            def each(&block)
              ctx = Braintrust::Contrib::Context.from(self)
              return super unless ctx&.[](:tracer) && !ctx[:consumed]

              ctx[:consumed] = true

              tracer = ctx[:tracer]
              params = ctx[:params]
              metadata = ctx[:metadata]
              responses_instance = ctx[:responses_instance]
              aggregated_events = []
              start_time = Braintrust::Internal::Time.measure
              time_to_first_token = nil

              tracer.in_span("openai.responses.create") do |span|
                responses_instance.send(:set_input, span, params)
                Common.set_json_attr(span, "braintrust.metadata", metadata)

                begin
                  super do |event|
                    time_to_first_token ||= Braintrust::Internal::Time.measure(start_time)
                    aggregated_events << event
                    block&.call(event)
                  end
                rescue => e
                  span.record_exception(e)
                  span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
                  raise
                end

                finalize_stream_span(span, aggregated_events, time_to_first_token, metadata)
              end
            end

            private

            def finalize_stream_span(span, aggregated_events, time_to_first_token, metadata)
              return if aggregated_events.empty?

              aggregated_output = Common.aggregate_responses_events(aggregated_events)
              Common.set_json_attr(span, "braintrust.output_json", aggregated_output[:output]) if aggregated_output[:output]

              # Set metrics
              metrics = {}
              if aggregated_output[:usage]
                metrics = Common.parse_usage_tokens(aggregated_output[:usage])
              end
              metrics["time_to_first_token"] = time_to_first_token
              Common.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?

              # Update metadata with response fields
              metadata["id"] = aggregated_output[:id] if aggregated_output[:id]
              Common.set_json_attr(span, "braintrust.metadata", metadata)
            end
          end
        end
      end
    end
  end
end
