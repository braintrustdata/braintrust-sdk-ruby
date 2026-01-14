# frozen_string_literal: true

module Braintrust
  module Remote
    # Shared utilities for working with scorers
    module ScorerUtils
      # Extract the name from a scorer object
      #
      # Scorers can define their name in several ways:
      # - A `name` attribute (e.g., InlineScorer, RemoteScorer)
      # - A `scorer_name` method
      # - Falls back to "scorer_{index}" if no name is found
      #
      # @param scorer [Object] A scorer object (Proc, class with #call or #score)
      # @param index [Integer] The scorer's index (used for fallback name)
      # @return [String] The scorer's name
      #
      # @example
      #   ScorerUtils.extract_name(my_scorer, 0)
      #   # => "accuracy"
      #
      #   ScorerUtils.extract_name(lambda { |**| 1.0 }, 2)
      #   # => "scorer_2"
      #
      def self.extract_name(scorer, index)
        if scorer.respond_to?(:name) && scorer.name
          scorer.name
        elsif scorer.respond_to?(:scorer_name)
          scorer.scorer_name
        else
          "scorer_#{index}"
        end
      end
    end
  end
end
