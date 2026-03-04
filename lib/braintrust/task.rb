# frozen_string_literal: true

module Braintrust
  # Task wraps a callable that processes inputs.
  # The block receives a Task::Args object with access to input, metadata, and tags.
  class Task
    # Read-only struct passed to tasks. Provides access to case data.
    class Args
      attr_reader :input, :metadata, :tags

      def initialize(input:, metadata: {}, tags: nil)
        @input = input
        @metadata = metadata
        @tags = tags
      end
    end

    attr_reader :name

    # Create a new task
    # @param name [String, Symbol, nil] Optional task name
    # @param block [Proc] The task implementation (receives Task::Args)
    def initialize(name = nil, &block)
      raise ArgumentError, "Must provide a block" unless block

      @name = name&.to_s || "task"
      @callable = block
      @wrapped_callable = wrap_callable(block)
    end

    # Call the task with a Task::Args object
    # @param task_args [Task::Args] The task arguments
    # @return [Object] Task output
    def call(task_args)
      @wrapped_callable.call(task_args)
    end

    private

    def wrap_callable(callable)
      arity = callable_arity(callable)

      case arity
      when 1, -1
        callable
      else
        raise ArgumentError, "Task must accept 1 parameter (got arity #{arity})"
      end
    end

    def callable_arity(callable)
      if callable.respond_to?(:arity)
        callable.arity
      elsif callable.respond_to?(:method)
        callable.method(:call).arity
      else
        1
      end
    end
  end
end
