# frozen_string_literal: true

module Braintrust
  module Contrib
    module RubyLLM
      module Instrumentation
        # Common utilities for RubyLLM instrumentation.
        module Common
          # Braintrust metrics for a RubyLLM message's token counts. ruby_llm 2.x renamed the cache
          # counts from cached_tokens/cache_creation_tokens to cache_read_tokens/cache_write_tokens.
          # @param message [Object] a RubyLLM message (anything responding to to_h)
          # @return [Hash<String, Integer>] normalized metrics, empty when no counts are reported
          def self.message_usage_metrics(message)
            return {} unless message.respond_to?(:to_h)

            counts = message.to_h
            usage = {
              "input_tokens" => counts[:input_tokens],
              "output_tokens" => counts[:output_tokens],
              "cached_tokens" => counts[:cached_tokens] || counts[:cache_read_tokens],
              "cache_creation_tokens" => counts[:cache_creation_tokens] || counts[:cache_write_tokens]
            }.compact

            usage.empty? ? {} : parse_usage_tokens(usage)
          end

          # Parse RubyLLM usage tokens into normalized Braintrust metrics.
          # RubyLLM normalizes token fields from all providers (OpenAI, Anthropic, etc.)
          # into a consistent format:
          #   - input_tokens: prompt tokens sent
          #   - output_tokens: completion tokens received
          #   - cached_tokens: tokens read from cache
          #   - cache_creation_tokens: tokens written to cache
          #
          # @param usage [Hash, Object] usage object from RubyLLM response
          # @return [Hash<String, Integer>] normalized metrics for Braintrust
          def self.parse_usage_tokens(usage)
            metrics = {}
            return metrics unless usage

            usage_hash = usage.respond_to?(:to_h) ? usage.to_h : usage
            return metrics unless usage_hash.is_a?(Hash)

            # RubyLLM normalized field mappings → Braintrust metrics
            field_map = {
              "input_tokens" => "prompt_tokens",
              "output_tokens" => "completion_tokens",
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
    end
  end
end
