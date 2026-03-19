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
    #   args you need. Extra kwargs are filtered out automatically.
    #
    #   Supported kwargs: +input:+, +expected:+, +output:+, +metadata:+, +trace:+
    # @return [Scorer::Block]
    # @raise [ArgumentError] if the block has unsupported arity
    def self.new(name = nil, &block)
      Block.new(name: name || DEFAULT_NAME, &block)
    end

    # Included into classes that +include Scorer+. Prepends KeywordFilter and
    # ResultNormalizer so #call receives only declared kwargs and always returns
    # Array<Hash>. Also provides a default #name and #call_parameters.
    module Callable
      # Normalizes the raw return value of #call into Array<Hash>.
      # Nested inside Callable because it depends on #name which Callable provides.
      module ResultNormalizer
        # @return [Array<Hash>] normalized score hashes with :score, :metadata, :name keys
        def call(**kwargs)
          normalize_score_result(super)
        end

        private

        # @param result [Numeric, Hash, Array<Hash>] raw return value from #call
        # @return [Array<Hash>] one or more score hashes with :score, :metadata, :name keys
        # @raise [ArgumentError] if any score value is not Numeric
        def normalize_score_result(result)
          case result
          when Array then result.map { |item| normalize_score_item(item) }
          when Hash then [normalize_score_item(result)]
          else
            raise ArgumentError, "#{name}: score must be Numeric, got #{result.inspect}" unless result.is_a?(Numeric)
            [{score: result, metadata: nil, name: name}]
          end
        end

        # Fills in missing :name from the scorer and validates :score.
        # @param item [Hash] a score hash with at least a :score key
        # @return [Hash] the same hash with :name set
        # @raise [ArgumentError] if :score is not Numeric
        def normalize_score_item(item)
          item[:name] ||= name
          raise ArgumentError, "#{item[:name]}: score must be Numeric, got #{item[:score].inspect}" unless item[:score].is_a?(Numeric)
          item
        end
      end

      # Infrastructure modules prepended onto every scorer class.
      # Used both to set up the ancestor chain and to skip past them in
      # #call_parameters so KeywordFilter sees the real call signature.
      PREPENDED = [Internal::Callable::KeywordFilter, ResultNormalizer].freeze

      # @param base [Class] the class including Callable
      def self.included(base)
        PREPENDED.each { |mod| base.prepend(mod) }
      end

      # Default name derived from the class name (e.g. FuzzyMatch -> "fuzzy_match").
      # @return [String]
      def name
        klass = self.class.name&.split("::")&.last
        return Scorer::DEFAULT_NAME unless klass
        klass.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end

      # Provides KeywordFilter with the actual call signature of the subclass.
      # Walks past PREPENDED modules in the ancestor chain so that user-defined
      # #call keyword params are correctly introspected.
      # Block overrides this to point directly at @block.parameters.
      # @return [Array<Array>] parameter list
      def call_parameters
        meth = method(:call)
        meth = meth.super_method while meth.super_method && PREPENDED.include?(meth.owner)
        meth.parameters
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
      # @return [Array<Hash>] normalized score results
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

  # @deprecated Use {Braintrust::Scorer::ID} instead.
  ScorerId = Scorer::ID
end
