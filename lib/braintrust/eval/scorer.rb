# frozen_string_literal: true

module Braintrust
  module Eval
    # Scorer wraps a scoring function that evaluates task output against expected values
    # Scorers can accept 3 params (input, expected, output), 4 params (input, expected, output, metadata),
    # or 5 params (input, expected, output, metadata, trace)
    # They can return a float, hash, or array of hashes
    class Scorer
      attr_reader :name

      # Create a new scorer
      # @param name_or_callable [String, Symbol, #call] Name or callable (if callable, name is auto-detected)
      # @param callable [#call, nil] Callable if name was provided separately
      # @param block [Proc, nil] Block if no callable provided
      def initialize(name_or_callable = nil, callable = nil, &block)
        # Determine name and callable from arguments
        if name_or_callable.nil? && callable.nil? && block.nil?
          raise ArgumentError, "Must provide callable or block"
        end

        # If first arg is a string/symbol, it's the name
        if name_or_callable.is_a?(String) || name_or_callable.is_a?(Symbol)
          @name = name_or_callable.to_s
          @callable = callable || block
          raise ArgumentError, "Must provide callable or block" unless @callable
        else
          # First arg is the callable, try to auto-detect name
          @callable = name_or_callable || callable || block
          @name = detect_name(@callable)
        end

        # Validate callable
        unless @callable.respond_to?(:call)
          raise ArgumentError, "Scorer must be callable (respond to :call)"
        end

        # Detect arity and wrap callable if needed
        @wrapped_callable = wrap_callable(@callable)
      end

      # Call the scorer
      # @param input [Object] The input to the task
      # @param expected [Object] The expected output
      # @param output [Object] The actual output from the task
      # @param metadata [Hash] Optional metadata
      # @param trace [TraceContext, nil] Optional trace context
      # @return [Float, Hash, Array] Score value(s)
      def call(input, expected, output, metadata = {}, trace = nil)
        @wrapped_callable.call(input, expected, output, metadata, trace)
      end

      private

      # Detect the name from a callable object
      # @param callable [#call] The callable
      # @return [String] The detected name
      def detect_name(callable)
        # Method objects have .name
        if callable.is_a?(Method)
          return callable.name.to_s
        end

        # Objects with .name method
        if callable.respond_to?(:name)
          return callable.name.to_s
        end

        # Fallback
        "scorer"
      end

      # Wrap the callable to always accept 5 parameters
      # @param callable [#call] The callable to wrap
      # @return [Proc] Wrapped callable that accepts 5 params
      def wrap_callable(callable)
        arity = callable_arity(callable)

        case arity
        when 3
          # Callable takes 3 params - wrap to ignore metadata and trace
          ->(input, expected, output, metadata, trace) {
            callable.call(input, expected, output)
          }
        when 4, -4
          # Callable takes 4 params - wrap to ignore trace
          # -4 means optional 4th param
          ->(input, expected, output, metadata, trace) {
            callable.call(input, expected, output, metadata)
          }
        when 5, -5, -1
          # Callable takes 5 params (or variadic with 5+)
          # -5 means optional 5th param
          # -1 means variadic (*args)
          callable
        else
          raise ArgumentError, "Scorer must accept 3, 4, or 5 parameters (got arity #{arity})"
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
  end
end
