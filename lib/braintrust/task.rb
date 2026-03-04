# frozen_string_literal: true

require_relative "internal/callable"

module Braintrust
  # Task wraps a callable that processes inputs.
  #
  # Use inline with a block (keyword args):
  #   task = Task.new("my_task") { |input:| process(input) }
  #
  # Or subclass and override #call:
  #   class MyTask < Braintrust::Task
  #     def call(input:, **)
  #       process(input)
  #     end
  #   end
  #
  # Legacy callables with 1 positional param are auto-wrapped when passed
  # through Eval.run for backwards compatibility.
  class Task
    include Internal::Callable

    private

    def callable_kind
      "task"
    end

    # Legacy positional wrapping: arity 1/-1 gets :input extracted.
    # Anything else falls through to Callable for keyword handling.
    def wrap_block(block)
      if !has_keywords?(block) && (block.arity == 1 || block.arity == -1)
        ->(**kw) { block.call(kw[:input]) }
      elsif has_keywords?(block) || block.arity == 0
        super
      else
        raise ArgumentError, "Task must accept keyword args or 1 positional param (got arity #{block.arity})"
      end
    end
  end
end
