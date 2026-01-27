# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

require_relative "../../support/otel"
require_relative "../../../internal/time"

module Braintrust
  module Contrib
    module RubyOpenAI
      module Instrumentation
        # Moderations API instrumentation for ruby-openai.
        # Provides module that can be prepended to OpenAI::Client to instrument the moderations method.
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
            # Wrap moderations method for ruby-openai gem
            # ruby-openai API: client.moderations(parameters: {...})
            def moderations(parameters:)
              tracer = Braintrust::Contrib.tracer_for(self)

              tracer.in_span("openai.moderations.create") do |span|
                metadata = build_moderations_metadata(parameters)
                set_moderations_input(span, parameters)

                response = nil
                time_to_first_token = Braintrust::Internal::Time.measure do
                  response = super(parameters: parameters)
                end

                set_moderations_output(span, response)
                set_moderations_metrics(span, time_to_first_token)
                finalize_moderations_metadata(span, metadata, response)

                response
              end
            end

            private

            def build_moderations_metadata(parameters)
              metadata = {
                "provider" => "openai",
                "endpoint" => "/v1/moderations"
              }

              Moderations::METADATA_FIELDS.each do |field|
                metadata[field.to_s] = parameters[field] if parameters.key?(field)
              end

              metadata
            end

            def set_moderations_input(span, parameters)
              return unless parameters[:input]
              Support::OTel.set_json_attr(span, "braintrust.input_json", parameters[:input])
            end

            def set_moderations_output(span, response)
              results = response["results"] || response[:results]
              return unless results
              Support::OTel.set_json_attr(span, "braintrust.output_json", results)
            end

            def set_moderations_metrics(span, time_to_first_token)
              metrics = {"time_to_first_token" => time_to_first_token}
              Support::OTel.set_json_attr(span, "braintrust.metrics", metrics)
            end

            def finalize_moderations_metadata(span, metadata, response)
              %w[id model].each do |field|
                value = response[field] || response[field.to_sym]
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
