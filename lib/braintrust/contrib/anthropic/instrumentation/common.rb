# frozen_string_literal: true

module Braintrust
  module Contrib
    module Anthropic
      module Instrumentation
        # Common utilities for Anthropic SDK instrumentation.
        module Common
          # Parse Anthropic SDK usage tokens into normalized Braintrust metrics.
          # Accumulates cache tokens into prompt_tokens and calculates total.
          # Works with both Hash objects and SDK response objects (via to_h).
          # @param usage [Hash, Object] usage object from Anthropic response
          # @return [Hash<String, Integer>] normalized metrics
          def self.parse_usage_tokens(usage)
            metrics = {}
            return metrics unless usage

            usage_hash = usage.respond_to?(:to_h) ? usage.to_h : usage
            return metrics unless usage_hash.is_a?(Hash)

            # Anthropic SDK field mappings → Braintrust metrics
            field_map = {
              "input_tokens" => "prompt_tokens",
              "output_tokens" => "completion_tokens",
              "cache_read_input_tokens" => "prompt_cached_tokens",
              "cache_creation_input_tokens" => "prompt_cache_creation_tokens"
            }

            usage_hash.each do |key, value|
              next unless value.is_a?(Numeric)
              key_str = key.to_s
              target = field_map[key_str]
              metrics[target] = value.to_i if target
            end

            # Cache-creation breakdown. When Anthropic returns the per-TTL
            # `cache_creation` breakdown, report the granular metrics
            # (prompt_cache_creation_5m_tokens / _1h_tokens) and drop the
            # aggregate prompt_cache_creation_tokens — the aggregate is just the
            # sum of the variants, so reporting both would double count.
            cache_creation_total = metrics["prompt_cache_creation_tokens"]
            apply_cache_creation_breakdown(metrics, usage_hash)

            # Accumulate cache tokens into prompt_tokens (matching TS/Python SDKs).
            # Use the original aggregate total when present, otherwise the
            # granular breakdown sum.
            creation_for_prompt = cache_creation_total ||
              (metrics["prompt_cache_creation_5m_tokens"] || 0) +
                (metrics["prompt_cache_creation_1h_tokens"] || 0)
            prompt_tokens = (metrics["prompt_tokens"] || 0) +
              (metrics["prompt_cached_tokens"] || 0) +
              creation_for_prompt
            metrics["prompt_tokens"] = prompt_tokens if prompt_tokens > 0

            # Calculate total
            if metrics.key?("prompt_tokens") && metrics.key?("completion_tokens")
              metrics["tokens"] = metrics["prompt_tokens"] + metrics["completion_tokens"]
            end

            metrics
          end

          # Map the nested `cache_creation` breakdown to per-TTL metrics and
          # remove the now-redundant aggregate. No-op when the breakdown is
          # absent or carries no positive values.
          # @param metrics [Hash] metrics accumulated so far (mutated)
          # @param usage_hash [Hash] raw Anthropic usage hash
          def self.apply_cache_creation_breakdown(metrics, usage_hash)
            breakdown = usage_hash["cache_creation"] || usage_hash[:cache_creation]
            breakdown = breakdown.to_h if breakdown.respond_to?(:to_h)
            return unless breakdown.is_a?(Hash)

            ttl_map = {
              "ephemeral_5m_input_tokens" => "prompt_cache_creation_5m_tokens",
              "ephemeral_1h_input_tokens" => "prompt_cache_creation_1h_tokens"
            }

            emitted = false
            ttl_map.each do |source, target|
              next unless breakdown.key?(source) || breakdown.key?(source.to_sym)
              value = breakdown[source] || breakdown[source.to_sym]
              next unless value.is_a?(Numeric)
              metrics[target] = value.to_i
              emitted = true
            end

            # When the per-TTL breakdown is present, drop the aggregate so we do
            # not double count (spec: "anthropic cache tokens only send 5m or
            # 1h variants").
            metrics.delete("prompt_cache_creation_tokens") if emitted
          end
        end
      end
    end
  end
end
