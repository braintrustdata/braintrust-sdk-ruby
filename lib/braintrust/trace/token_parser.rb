# frozen_string_literal: true

module Braintrust
  module Trace
    # Shared token usage parsing utilities for normalizing token metrics across providers
    # Standardizes field names to Braintrust conventions:
    # - prompt_tokens: Input/prompt tokens
    # - completion_tokens: Output/completion tokens
    # - tokens: Total tokens
    # - prompt_cached_tokens: Cached prompt tokens (read from cache)
    # - prompt_cache_creation_tokens: Tokens used to create cache
    module TokenParser
      # Normalize token field names across different provider formats
      # @param usage [Hash, Object] usage object from API response
      # @param field_mappings [Hash] provider-specific field name mappings
      # @return [Hash<String, Integer>] metrics hash with normalized names
      def self.parse_usage_tokens(usage, field_mappings: {})
        metrics = {}
        return metrics unless usage

        # Convert to hash if it's an object
        usage_hash = usage.respond_to?(:to_h) ? usage.to_h : usage
        return metrics unless usage_hash.is_a?(Hash)

        # Default field mappings (can be overridden per provider)
        default_mappings = {
          "input_tokens" => "prompt_tokens",
          "prompt_tokens" => "prompt_tokens",
          "output_tokens" => "completion_tokens",
          "completion_tokens" => "completion_tokens",
          "total_tokens" => "tokens",
          "tokens" => "tokens",
          "cached_tokens" => "prompt_cached_tokens",
          "cache_read_input_tokens" => "prompt_cached_tokens",
          "cache_creation_tokens" => "prompt_cache_creation_tokens",
          "cache_creation_input_tokens" => "prompt_cache_creation_tokens"
        }

        mappings = default_mappings.merge(field_mappings)

        # Process each field in the usage hash
        usage_hash.each do |key, value|
          next unless value.is_a?(Numeric)
          key_str = key.to_s

          # Apply field mapping if available
          if mappings.key?(key_str)
            target_field = mappings[key_str]
            # For prompt_tokens and tokens, we may need to accumulate multiple sources
            if target_field == "prompt_tokens" && metrics.key?(target_field)
              metrics[target_field] += value.to_i
            else
              metrics[target_field] ||= value.to_i
            end
          else
            # Keep unmapped numeric fields as-is (future-proofing)
            metrics[key_str] = value.to_i
          end
        end

        # Calculate total tokens if not provided
        if !metrics.key?("tokens") && metrics.key?("prompt_tokens") && metrics.key?("completion_tokens")
          total = metrics["prompt_tokens"] + metrics["completion_tokens"]
          # Add cache creation tokens to total if present
          total += metrics["prompt_cache_creation_tokens"] if metrics.key?("prompt_cache_creation_tokens")
          metrics["tokens"] = total
        end

        metrics
      end
    end
  end
end
