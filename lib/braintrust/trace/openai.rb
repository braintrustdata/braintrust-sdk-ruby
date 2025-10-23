# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

module Braintrust
  module Trace
    module OpenAI
      # Parse usage tokens from OpenAI API response, handling nested token_details
      # Maps OpenAI field names to Braintrust standard names:
      # - input_tokens → prompt_tokens
      # - output_tokens → completion_tokens
      # - total_tokens → tokens
      # - *_tokens_details.* → prefix_*
      #
      # @param usage [Hash, Object] usage object from OpenAI response
      # @return [Hash<String, Integer>] metrics hash with normalized names
      def self.parse_usage_tokens(usage)
        metrics = {}
        return metrics unless usage

        # Convert to hash if it's an object
        usage_hash = usage.respond_to?(:to_h) ? usage.to_h : usage

        usage_hash.each do |key, value|
          key_str = key.to_s

          # Handle nested *_tokens_details objects
          if key_str.end_with?("_tokens_details")
            # Convert to hash if it's an object (OpenAI gem returns objects)
            details_hash = value.respond_to?(:to_h) ? value.to_h : value
            next unless details_hash.is_a?(Hash)

            # Extract prefix (e.g., "prompt" from "prompt_tokens_details")
            prefix = key_str.sub(/_tokens_details$/, "")
            # Translate "input" → "prompt", "output" → "completion"
            prefix = translate_metric_prefix(prefix)

            # Process nested fields (e.g., cached_tokens, reasoning_tokens)
            details_hash.each do |detail_key, detail_value|
              next unless detail_value.is_a?(Numeric)
              metrics["#{prefix}_#{detail_key}"] = detail_value.to_i
            end
          elsif value.is_a?(Numeric)
            # Handle top-level token fields
            case key_str
            when "input_tokens"
              metrics["prompt_tokens"] = value.to_i
            when "output_tokens"
              metrics["completion_tokens"] = value.to_i
            when "total_tokens"
              metrics["tokens"] = value.to_i
            else
              # Keep other numeric fields as-is (future-proofing)
              metrics[key_str] = value.to_i
            end
          end
        end

        metrics
      end

      # Translate metric prefix to be consistent between different API formats
      # @param prefix [String] the prefix to translate
      # @return [String] translated prefix
      def self.translate_metric_prefix(prefix)
        case prefix
        when "input"
          "prompt"
        when "output"
          "completion"
        else
          prefix
        end
      end

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
              # Pass through all message fields to preserve tool_calls, tool_call_id, name, etc.
              if params[:messages]
                messages_array = params[:messages].map(&:to_h)
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

              # Set metrics (token usage with advanced details)
              if response.respond_to?(:usage) && response.usage
                metrics = Braintrust::Trace::OpenAI.parse_usage_tokens(response.usage)
                span.set_attribute("braintrust.metrics", JSON.generate(metrics)) unless metrics.empty?
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
