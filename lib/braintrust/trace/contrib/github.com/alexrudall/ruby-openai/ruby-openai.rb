# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

module Braintrust
  module Trace
    module AlexRudall
      module RubyOpenAI
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
        # - prompt_tokens → prompt_tokens
        # - completion_tokens → completion_tokens
        # - total_tokens → tokens
        #
        # @param usage [Hash] usage hash from OpenAI response
        # @return [Hash<String, Integer>] metrics hash with normalized names
        def self.parse_usage_tokens(usage)
          metrics = {}
          return metrics unless usage

          # Basic token counts
          metrics["prompt_tokens"] = usage["prompt_tokens"].to_i if usage["prompt_tokens"]
          metrics["completion_tokens"] = usage["completion_tokens"].to_i if usage["completion_tokens"]
          metrics["total_tokens"] = usage["total_tokens"].to_i if usage["total_tokens"]

          # Rename total_tokens to tokens for consistency
          metrics["tokens"] = metrics.delete("total_tokens") if metrics["total_tokens"]

          metrics
        end

        # Wrap an OpenAI::Client (ruby-openai gem) to automatically create spans
        # Supports both synchronous and streaming requests
        # @param client [OpenAI::Client] the OpenAI client to wrap
        # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
        def self.wrap(client, tracer_provider: nil)
          tracer_provider ||= ::OpenTelemetry.tracer_provider

          # Wrap chat completions
          wrap_chat(client, tracer_provider)

          client
        end

        # Wrap chat API
        # @param client [OpenAI::Client] the OpenAI client
        # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
        def self.wrap_chat(client, tracer_provider)
          # Create a wrapper module that intercepts the chat method
          wrapper = Module.new do
            define_method(:chat) do |parameters:|
              tracer = tracer_provider.tracer("braintrust")

              tracer.in_span("openai.chat.completions.create") do |span|
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
                      true  # Just mark as streaming
                    else
                      parameters[field_sym]
                    end
                  end
                end

                # Set input messages as JSON
                if parameters[:messages]
                  span.set_attribute("braintrust.input_json", JSON.generate(parameters[:messages]))
                end

                begin
                  # Call the original method
                  response = super(parameters: parameters)

                  # Set output (choices) as JSON
                  if response && response["choices"]&.any?
                    span.set_attribute("braintrust.output_json", JSON.generate(response["choices"]))
                  end

                  # Set metrics (token usage)
                  if response && response["usage"]
                    metrics = Braintrust::Trace::AlexRudall::RubyOpenAI.parse_usage_tokens(response["usage"])
                    span.set_attribute("braintrust.metrics", JSON.generate(metrics)) unless metrics.empty?
                  end

                  # Add response metadata fields
                  if response
                    metadata["id"] = response["id"] if response["id"]
                    metadata["created"] = response["created"] if response["created"]
                    metadata["system_fingerprint"] = response["system_fingerprint"] if response["system_fingerprint"]
                    metadata["service_tier"] = response["service_tier"] if response["service_tier"]
                  end

                  # Set metadata ONCE at the end with complete hash
                  span.set_attribute("braintrust.metadata", JSON.generate(metadata))

                  response
                rescue => e
                  # Record exception in span
                  span.record_exception(e)
                  span.status = OpenTelemetry::Trace::Status.error("Exception: #{e.class} - #{e.message}")
                  raise
                end
              end
            end
          end

          # Prepend the wrapper to the client's singleton class
          client.singleton_class.prepend(wrapper)
        end
      end
    end
  end
end
