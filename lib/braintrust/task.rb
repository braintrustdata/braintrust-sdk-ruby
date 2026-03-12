# frozen_string_literal: true

require_relative "internal/callable"

module Braintrust
  # Task wraps a callable that processes inputs.
  #
  # Use inline with a block (keyword args):
  #   task = Task.new("my_task") { |input:| process(input) }
  #
  # Or include in a class and define #call with keyword args:
  #   class MyTask
  #     include Braintrust::Task
  #
  #     def call(input:)
  #       process(input)
  #     end
  #   end
  #
  # Legacy callables with 1 positional param are auto-wrapped for
  # backwards compatibility but emit a deprecation warning.
  module Task
    DEFAULT_NAME = "task"

    # @param base [Class] the class including Task
    def self.included(base)
      base.include(Callable)
    end

    # Create a block-based task.
    #
    # @param name [String, nil] optional name (defaults to "task")
    # @param block [Proc] the task implementation; declare only the keyword
    #   args you need (e.g. +|input:|+). Extra kwargs passed by the caller
    #   are filtered out automatically.
    # @return [Task::Block]
    # @raise [ArgumentError] if the block has unsupported arity
    def self.new(name = nil, &block)
      Block.new(name: name || DEFAULT_NAME, &block)
    end

    # Included into classes that +include Task+. Prepends KeywordFilter
    # so #call receives only its declared kwargs, and provides a default #name.
    module Callable
      # @param base [Class] the class including Callable
      def self.included(base)
        base.prepend(Internal::Callable::KeywordFilter)
      end

      # Default name derived from the class name (e.g. MyTask -> "my_task").
      # @return [String]
      def name
        klass = self.class.name&.split("::")&.last
        return Task::DEFAULT_NAME unless klass
        klass.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end
    end

    # Block-based task. Stores a Proc and delegates #call to it.
    # Includes Task so it satisfies +Task ===+ checks (e.g. in Context::Factory).
    # Exposes #call_parameters so KeywordFilter can introspect the block's
    # declared kwargs rather than Block#call's **kwargs signature.
    class Block
      include Task

      # @return [String]
      attr_reader :name

      # @param name [String] task name
      # @param block [Proc] task implementation
      def initialize(name: DEFAULT_NAME, &block)
        @name = name
        @block = wrap_block(block)
      end

      # @param kwargs [Hash] keyword arguments (filtered by KeywordFilter)
      # @return [Object] result of the block
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

      # Legacy positional wrapping: arity 1/-1 gets :input extracted.
      # Keyword and zero-arity blocks are stored raw; KeywordFilter handles filtering at call time.
      # @param block [Proc]
      # @return [Proc]
      def wrap_block(block)
        params = block.parameters
        if Internal::Callable::KeywordFilter.has_any_keywords?(params) || block.arity == 0
          block
        elsif block.arity == 1 || block.arity == -1
          Log.warn_once(:task_positional, "Task with positional param (input) is deprecated. Use keyword args: ->(input:) { ... } instead.")
          ->(**kw) { block.call(kw[:input]) }
        else
          raise ArgumentError, "Task must accept keyword args or 1 positional param (got arity #{block.arity})"
        end
      end
    end
  end
end
