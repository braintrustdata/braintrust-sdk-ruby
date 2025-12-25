# frozen_string_literal: true

module Braintrust
  module Trace
    # Parse Anthropic usage tokens into normalized Braintrust metrics.
    # Accumulates cache tokens into prompt_tokens and calculates total.
    # @param usage [Hash, Object] usage object from Anthropic response
    # @return [Hash<String, Integer>] normalized metrics
    def self.parse_anthropic_usage_tokens(usage)
      metrics = {}
      return metrics unless usage

      usage_hash = usage.respond_to?(:to_h) ? usage.to_h : usage
      return metrics unless usage_hash.is_a?(Hash)

      # Field mappings: Anthropic → Braintrust
      # Also handles RubyLLM's simplified cache field names
      field_map = {
        "input_tokens" => "prompt_tokens",
        "output_tokens" => "completion_tokens",
        "cache_read_input_tokens" => "prompt_cached_tokens",
        "cache_creation_input_tokens" => "prompt_cache_creation_tokens",
        # RubyLLM uses simplified names
        "cached_tokens" => "prompt_cached_tokens",
        "cache_creation_tokens" => "prompt_cache_creation_tokens"
      }

      usage_hash.each do |key, value|
        next unless value.is_a?(Numeric)
        key_str = key.to_s
        target = field_map[key_str]
        metrics[target] = value.to_i if target
      end

      # Accumulate cache tokens into prompt_tokens (matching TS/Python SDKs)
      prompt_tokens = (metrics["prompt_tokens"] || 0) +
        (metrics["prompt_cached_tokens"] || 0) +
        (metrics["prompt_cache_creation_tokens"] || 0)
      metrics["prompt_tokens"] = prompt_tokens if prompt_tokens > 0

      # Calculate total
      if metrics.key?("prompt_tokens") && metrics.key?("completion_tokens")
        metrics["tokens"] = metrics["prompt_tokens"] + metrics["completion_tokens"]
      end

      metrics
    end
  end
end
