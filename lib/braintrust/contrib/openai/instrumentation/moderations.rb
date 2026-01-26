# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

require_relative "../../../internal/time"
require_relative "../../support/otel"

module Braintrust
  module Contrib
    module OpenAI
      module Instrumentation
        # Moderations API instrumentation for OpenAI.
        # Wraps create() method to create spans.
        module Moderations
          def self.included(base)
            base.prepend(InstanceMethods) unless applied?(base)
          end

          def self.applied?(base)
            base.ancestors.include?(InstanceMethods)
          end

          METADATA_FIELDS = %i[
            model
          ].freeze

          module InstanceMethods
            # Wrap non-streaming create method
            def create(**params)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)

              tracer.in_span("openai.moderations.create") do |span|
                metadata = build_metadata(params)

                set_input(span, params)

                response = nil
                time_to_first_token = Braintrust::Internal::Time.measure do
                  response = super
                end

                set_output(span, response)
                set_metrics(span, time_to_first_token)
                finalize_metadata(span, metadata, response)

                response
              end
            end

            private

            def build_metadata(params)
              metadata = {
                "provider" => "openai",
                "endpoint" => "/v1/moderations"
              }
              Moderations::METADATA_FIELDS.each do |field|
                metadata[field.to_s] = params[field] if params.key?(field)
              end
              metadata
            end

            def set_input(span, params)
              return unless params[:input]

              Support::OTel.set_json_attr(span, "braintrust.input_json", params[:input])
            end

            def set_output(span, response)
              return unless response.respond_to?(:results) && response.results

              Support::OTel.set_json_attr(span, "braintrust.output_json", response.results)
            end

            def set_metrics(span, time_to_first_token)
              metrics = {}
              metrics["time_to_first_token"] = time_to_first_token
              Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
            end

            def finalize_metadata(span, metadata, response)
              metadata["id"] = response.id if response.respond_to?(:id) && response.id
              metadata["model"] = response.model if response.respond_to?(:model) && response.model
              Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)
            end
          end
        end
      end
    end
  end
end
