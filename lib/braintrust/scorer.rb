# frozen_string_literal: true

require_relative "internal/callable"

module Braintrust
  # Scorer wraps a scoring function that evaluates task output against expected values.
  #
  # Use inline with a block (keyword args):
  #   scorer = Scorer.new("my_scorer") { |output:, expected:| output == expected ? 1.0 : 0.0 }
  #
  # Or subclass and override #call:
  #   class FuzzyMatch < Braintrust::Scorer
  #     def name
  #       "fuzzy_match"
  #     end
  #
  #     def call(output:, expected:, **)
  #       output == expected ? 1.0 : 0.0
  #     end
  #   end
  #
  # Legacy callables with 3 or 4 positional params are auto-wrapped when passed
  # through Eval.run for backwards compatibility.
  class Scorer
    include Internal::Callable

    private

    def callable_kind
      "scorer"
    end

    # Legacy positional wrapping: arity 3/4/-4/-1 maps to (input, expected, output[, metadata]).
    # Anything else falls through to Callable for keyword handling.
    def wrap_block(block)
      if has_keywords?(block)
        super
      else
        case block.arity
        when 3
          ->(**kw) { block.call(kw[:input], kw[:expected], kw[:output]) }
        when 4, -4
          ->(**kw) { block.call(kw[:input], kw[:expected], kw[:output], kw[:metadata]) }
        when -1
          ->(**kw) { block.call(kw[:input], kw[:expected], kw[:output], kw[:metadata]) }
        when 0
          super
        else
          raise ArgumentError, "Scorer must accept keyword args or 3-4 positional params (got arity #{block.arity})"
        end
      end
    end
  end

  # Value object wrapping a remote scorer function UUID.
  # Used by Eval.run to distinguish remote scorers from local callables.
  ScorerId = Struct.new(:function_id, :version, keyword_init: true)
end
