# frozen_string_literal: true

module Braintrust
  module Contrib
    module LlmRb
      module Instrumentation
        # Common utilities for llm.rb instrumentation.
        module Common
          # Parse LLM::Usage into normalized Braintrust metrics.
          # LLM::Usage has: input_tokens, output_tokens, reasoning_tokens, total_tokens
          #
          # @param usage [LLM::Usage, nil] usage struct from llm.rb response
          # @return [Hash<String, Integer>] normalized metrics for Braintrust
          def self.parse_usage_tokens(usage)
            return {} unless usage

            input = usage.respond_to?(:input_tokens) ? usage.input_tokens : nil
            output = usage.respond_to?(:output_tokens) ? usage.output_tokens : nil
            reasoning = usage.respond_to?(:reasoning_tokens) ? usage.reasoning_tokens : nil
            total = usage.respond_to?(:total_tokens) ? usage.total_tokens : nil

            metrics = {}
            metrics["prompt_tokens"] = input.to_i if input
            metrics["completion_tokens"] = output.to_i if output
            metrics["completion_reasoning_tokens"] = reasoning.to_i if reasoning && reasoning.to_i > 0

            if metrics.key?("prompt_tokens") && metrics.key?("completion_tokens")
              metrics["tokens"] = metrics["prompt_tokens"] + metrics["completion_tokens"]
            elsif total
              metrics["tokens"] = total.to_i
            end

            metrics
          end
        end
      end
    end
  end
end
