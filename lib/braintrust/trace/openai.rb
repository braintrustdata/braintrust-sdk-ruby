# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

module Braintrust
  module Trace
    module OpenAI
      # Wrap an OpenAI::Client to automatically create spans for chat completions
      # @param client [OpenAI::Client] the OpenAI client to wrap
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
      def self.wrap(client, tracer_provider: nil)
        tracer_provider ||= ::OpenTelemetry.tracer_provider

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
              if params[:messages]
                messages_array = params[:messages].map do |msg|
                  {role: msg[:role].to_s, content: msg[:content]}
                end
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

              # Set metrics (token usage)
              if response.respond_to?(:usage) && response.usage
                metrics = {}
                metrics["prompt_tokens"] = response.usage.prompt_tokens if response.usage.prompt_tokens
                metrics["completion_tokens"] = response.usage.completion_tokens if response.usage.completion_tokens
                metrics["tokens"] = response.usage.total_tokens if response.usage.total_tokens
                span.set_attribute("braintrust.metrics", JSON.generate(metrics))
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
        end

        # Prepend the wrapper to the completions resource
        client.chat.completions.singleton_class.prepend(wrapper)

        client
      end
    end
  end
end
