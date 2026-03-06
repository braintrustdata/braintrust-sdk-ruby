# frozen_string_literal: true

require_relative "internal/callable"

module Braintrust
  # Scorer wraps a scoring function that evaluates task output against expected values.
  #
  # Use inline with a block (keyword args):
  #   scorer = Scorer.new("my_scorer") { |expected:, output:| output == expected ? 1.0 : 0.0 }
  #
  # Or include in a class and define #call with keyword args:
  #   class FuzzyMatch
  #     include Braintrust::Scorer
  #
  #     def call(expected:, output:)
  #       output == expected ? 1.0 : 0.0
  #     end
  #   end
  #
  # Legacy callables with 3 or 4 positional params are auto-wrapped for
  # backwards compatibility but emit a deprecation warning.
  module Scorer
    DEFAULT_NAME = "scorer"

    # @param base [Class] the class including Scorer
    def self.included(base)
      base.include(Callable)
    end

    # Create a block-based scorer.
    #
    # @param name [String, nil] optional name (defaults to "scorer")
    # @param block [Proc] the scoring implementation; declare only the keyword
    #   args you need (e.g. +|expected:, output:|+). Extra kwargs passed by the
    #   caller are filtered out automatically.
    # @return [Scorer::Block]
    # @raise [ArgumentError] if the block has unsupported arity
    def self.new(name = nil, &block)
      Block.new(name: name || DEFAULT_NAME, &block)
    end

    # Included into classes that +include Scorer+. Prepends KeywordFilter
    # so #call receives only its declared kwargs, and provides a default #name.
    module Callable
      # @param base [Class] the class including Callable
      def self.included(base)
        base.prepend(Internal::Callable::KeywordFilter)
      end

      # Default name derived from the class name (e.g. FuzzyMatch -> "fuzzy_match").
      # @return [String]
      def name
        klass = self.class.name&.split("::")&.last
        return Scorer::DEFAULT_NAME unless klass
        klass.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end
    end

    # Block-based scorer. Stores a Proc and delegates #call to it.
    # Includes Scorer so it satisfies +Scorer ===+ checks (e.g. in Context::Factory).
    # Exposes #call_parameters so KeywordFilter can introspect the block's
    # declared kwargs rather than Block#call's **kwargs signature.
    class Block
      include Scorer

      # @return [String]
      attr_reader :name

      # @param name [String] scorer name
      # @param block [Proc] scoring implementation
      def initialize(name: DEFAULT_NAME, &block)
        @name = name
        @block = wrap_block(block)
      end

      # @param kwargs [Hash] keyword arguments (filtered by KeywordFilter)
      # @return [Float, Hash, Array] score result
      def call(**kwargs)
        @block.call(**kwargs)
      end

      # Exposes the block's parameter list so KeywordFilter can filter
      # kwargs to match the block's declared keywords.
      # @return [Array<Array>] parameter list from Proc#parameters
      def call_parameters
        @block.parameters
      end

      private

      # Legacy positional wrapping: arity 3/4/-4/-1 maps to (input, expected, output[, metadata]).
      # Keyword and zero-arity blocks are stored raw; KeywordFilter handles filtering at call time.
      # @param block [Proc]
      # @return [Proc]
      def wrap_block(block)
        params = block.parameters
        if Internal::Callable::KeywordFilter.has_any_keywords?(params) || block.arity == 0
          block
        else
          case block.arity
          when 3
            Log.warn_once(:scorer_positional_3, "Scorer with positional params (input, expected, output) is deprecated. Use keyword args: |input:, expected:, output:| instead.")
            ->(**kw) { block.call(kw[:input], kw[:expected], kw[:output]) }
          when 4, -4, -1
            Log.warn_once(:scorer_positional_4, "Scorer with positional params (input, expected, output, metadata) is deprecated. Use keyword args: |input:, expected:, output:, metadata:| instead.")
            ->(**kw) { block.call(kw[:input], kw[:expected], kw[:output], kw[:metadata]) }
          else
            raise ArgumentError, "Scorer must accept keyword args or 3-4 positional params (got arity #{block.arity})"
          end
        end
      end
    end

    # Value object wrapping a remote scorer function UUID.
    # Used by Eval.run to distinguish remote scorers from local callables.
    ID = Struct.new(:function_id, :version, keyword_init: true)
  end
end
