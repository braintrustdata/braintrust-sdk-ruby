# frozen_string_literal: true

module Braintrust
  # Scorer wraps a scoring function that evaluates task output against expected values.
  #
  # Use inline with a block:
  #   scorer = Scorer.new("my_scorer") { |args| args.output == args.expected ? 1.0 : 0.0 }
  #
  # Or subclass and override #call:
  #   class FuzzyMatch < Braintrust::Scorer
  #     def call(args)
  #       # scoring logic using args.input, args.expected, args.output, args.metadata
  #       1.0
  #     end
  #   end
  #
  # Legacy callables with 3 or 4 positional params are auto-wrapped when passed
  # through Eval.run for backwards compatibility.
  class Scorer
    # Read-only struct passed to scorers. Provides access to all case data.
    class Args
      attr_reader :input, :expected, :output, :metadata, :tags, :trace

      def initialize(input:, expected:, output:, metadata: {}, tags: nil, trace: nil)
        @input = input
        @expected = expected
        @output = output
        @metadata = metadata
        @tags = tags
        @trace = trace
      end
    end

    attr_reader :name

    NOT_IMPLEMENTED = ->(_) { raise NotImplementedError, "Must provide a block or override #call" }
    private_constant :NOT_IMPLEMENTED

    # Create a new scorer
    # @param name [String, Symbol, nil] Optional scorer name
    # @param block [Proc, nil] The scorer implementation (optional if subclassing)
    def initialize(name = nil, &block)
      @name = name&.to_s || default_name
      @block = block ? wrap_block(block) : NOT_IMPLEMENTED
    end

    # Call the scorer with a Scorer::Args object.
    # Override this method in subclasses, or provide a block to the constructor.
    # @param scorer_args [Scorer::Args] The scorer arguments
    # @return [Float, Hash, Array] Score value(s)
    def call(scorer_args)
      @block.call(scorer_args)
    end

    private

    # Derive a default name from the class name (e.g. FuzzyMatchScorer -> "fuzzy_match_scorer")
    # @return [String]
    def default_name
      klass = self.class.name&.split("::")&.last
      return "scorer" unless klass && klass != "Scorer"
      klass.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end

    # Wrap the callable to accept a single Scorer::Args object.
    # Arity-1 callables receive Args directly; legacy arities are auto-wrapped.
    # @param callable [#call] The callable to wrap
    # @return [Proc] Wrapped callable that accepts a single Scorer::Args
    def wrap_block(callable)
      arity = callable_arity(callable)

      case arity
      when 1
        callable
      when 3
        ->(args) { callable.call(args.input, args.expected, args.output) }
      when 4, -4
        ->(args) { callable.call(args.input, args.expected, args.output, args.metadata) }
      when -1
        ->(args) { callable.call(args.input, args.expected, args.output, args.metadata) }
      else
        raise ArgumentError, "Scorer must accept 1, 3, or 4 parameters (got arity #{arity})"
      end
    end

    # Get the arity of a callable
    # @param callable [#call] The callable
    # @return [Integer] The arity
    def callable_arity(callable)
      if callable.respond_to?(:arity)
        callable.arity
      elsif callable.respond_to?(:method)
        callable.method(:call).arity
      else
        # Assume 3 params if we can't detect
        3
      end
    end
  end

  # Value object wrapping a remote scorer function UUID.
  # Used by Eval.run to distinguish remote scorers from local callables.
  ScorerId = Struct.new(:function_id, :version, keyword_init: true)
end
