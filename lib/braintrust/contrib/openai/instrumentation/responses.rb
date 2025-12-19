# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

require_relative "common"

module Braintrust
  module Contrib
    module OpenAI
      module Instrumentation
        # Responses API instrumentation for OpenAI.
        # Provides modules that can be prepended to OpenAI::Client to instrument responses API.
        module Responses
          def self.included(base)
            # Guard against double-wrapping for: Check if patch is already in the ancestor chain.
            # This prevents double instrumentation if class-level patching was already applied,
            # and this patch is being applied to a singleton-class. (Special case.)
            #
            # Ruby's prepend() doesn't check the full inheritance chain, so without this guard,
            # the instrumentation could be added twice.
            base.prepend(InstanceMethods) unless base.ancestors.include?(InstanceMethods)
          end

          def self.applied?(base)
            base.ancestors.include?(InstanceMethods)
          end

          module InstanceMethods
            # Wrap non-streaming create method
            def create(**params)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)

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
                  metrics = Common.parse_usage_tokens(response.usage)
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
            def stream(**params)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)
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
                stream = super
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
                  aggregated_output = Common.aggregate_responses_events(aggregated_events)
                  Common.set_json_attr(span, "braintrust.output_json", aggregated_output[:output]) if aggregated_output[:output]

                  # Set metrics if usage is included
                  if aggregated_output[:usage]
                    metrics = Common.parse_usage_tokens(aggregated_output[:usage])
                    Common.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
                  end

                  # Update metadata with response fields
                  metadata["id"] = aggregated_output[:id] if aggregated_output[:id]
                  Common.set_json_attr(span, "braintrust.metadata", metadata)
                end

                span.finish
              end

              stream
            end
          end
        end
      end
    end
  end
end
