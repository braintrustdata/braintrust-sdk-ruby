# frozen_string_literal: true

module Braintrust
  module Contrib
    module Support
      # OpenAI API-specific utilities shared across OpenAI integrations.
      # These work with normalized data structures (hashes), not library-specific objects.
      module OpenAI
        # Parse OpenAI usage tokens into normalized Braintrust metrics.
        # Handles standard fields and *_tokens_details nested objects.
        # Works with both Hash objects and SDK response objects (via to_h).
        # @param usage [Hash, Object] usage object from OpenAI response
        # @return [Hash<String, Integer>] normalized metrics
        def self.parse_usage_tokens(usage)
          metrics = {}
          return metrics unless usage

          usage_hash = usage.respond_to?(:to_h) ? usage.to_h : usage
          return metrics unless usage_hash.is_a?(Hash)

          # Field mappings: OpenAI → Braintrust
          # Supports both Chat Completions API (prompt_tokens, completion_tokens)
          # and Responses API (input_tokens, output_tokens)
          field_map = {
            "prompt_tokens" => "prompt_tokens",
            "completion_tokens" => "completion_tokens",
            "total_tokens" => "tokens",
            # Responses API uses different field names
            "input_tokens" => "prompt_tokens",
            "output_tokens" => "completion_tokens"
          }

          # Prefix mappings for *_tokens_details
          prefix_map = {
            "prompt" => "prompt",
            "completion" => "completion",
            # Responses API uses input/output prefixes
            "input" => "prompt",
            "output" => "completion"
          }

          usage_hash.each do |key, value|
            key_str = key.to_s

            if value.is_a?(Numeric)
              target = field_map[key_str]
              metrics[target] = value.to_i if target
            elsif key_str.end_with?("_tokens_details")
              # Convert to hash if it's an object (OpenAI SDK returns objects)
              details_hash = value.respond_to?(:to_h) ? value.to_h : value
              next unless details_hash.is_a?(Hash)

              raw_prefix = key_str.sub(/_tokens_details$/, "")
              prefix = prefix_map[raw_prefix] || raw_prefix
              details_hash.each do |detail_key, detail_value|
                next unless detail_value.is_a?(Numeric)
                metrics["#{prefix}_#{detail_key}"] = detail_value.to_i
              end
            end
          end

          # Calculate total if missing
          if !metrics.key?("tokens") && metrics.key?("prompt_tokens") && metrics.key?("completion_tokens")
            metrics["tokens"] = metrics["prompt_tokens"] + metrics["completion_tokens"]
          end

          metrics
        end
      end
    end
  end
end
