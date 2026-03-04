# frozen_string_literal: true

module Braintrust
  module Internal
    # Shared mixin for Task and Scorer that provides:
    # - Block wrapping with keyword argument filtering
    # - Default name derivation from class name
    # - NOT_IMPLEMENTED sentinel for subclasses without blocks
    #
    # Keyword filtering: blocks that declare specific keyword params (e.g. |output:, expected:|)
    # are automatically wrapped to receive only their declared kwargs, even when the caller
    # passes additional kwargs like tags:, metadata:, etc. This avoids Ruby 3.2+
    # ArgumentError for unknown keywords.
    #
    # Blocks with **keyrest pass through all kwargs unfiltered.
    #
    # Classes that include this mixin can override #wrap_block to handle
    # legacy positional blocks before calling super for keyword handling.
    module Callable
      NOT_IMPLEMENTED = ->(**_) { raise NotImplementedError, "Must provide a block or override #call" }
      private_constant :NOT_IMPLEMENTED

      attr_reader :name

      # @param name [String, Symbol, nil] Optional name
      # @param block [Proc, nil] Implementation block (optional if subclassing)
      def initialize(name = nil, &block)
        @name = name&.to_s || default_name
        @block = block ? wrap_block(block) : NOT_IMPLEMENTED
      end

      # Call the callable with keyword arguments.
      # Override in subclasses, or provide a block to the constructor.
      def call(**kwargs)
        @block.call(**kwargs)
      end

      private

      # Derive a default name from the class name (e.g. FuzzyMatch -> "fuzzy_match").
      # Falls back to callable_kind ("task" or "scorer") for the base class.
      # @return [String]
      def default_name
        klass = self.class.name&.split("::")&.last
        return callable_kind unless klass && klass != callable_kind.capitalize
        klass.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end

      # Subclasses must override to return "task" or "scorer".
      # Used as fallback name when the class is the base class itself.
      # @return [String]
      def callable_kind
        raise NotImplementedError, "#{self.class} must implement #callable_kind"
      end

      # Wrap the block to accept keyword arguments.
      # - Has keyword params but NO keyrest: filter kwargs to declared keys only
      # - Has keyword params WITH keyrest: pass through as-is
      # - Zero arity: pass through
      # - Anything else: raise (override in subclass to handle legacy positional blocks)
      # @param block [Proc] The block to wrap
      # @return [Proc] Wrapped block that accepts keyword arguments
      def wrap_block(block)
        if has_keywords?(block)
          has_keyrest = block.parameters.any? { |type, _| type == :keyrest }
          has_keyrest ? block : wrap_keyword_block(block)
        elsif block.arity == 0
          block
        else
          raise ArgumentError, "#{self.class} does not accept positional block params (got arity #{block.arity})"
        end
      end

      # Whether the block declares any keyword parameters (key, keyreq, or keyrest).
      # @param block [Proc]
      # @return [Boolean]
      def has_keywords?(block)
        block.parameters.any? { |type, _| type == :keyreq || type == :key || type == :keyrest }
      end

      # Build a wrapper that slices kwargs to only the keys declared by the block.
      # @param block [Proc] A block with explicit keyword params (no **)
      # @return [Proc]
      def wrap_keyword_block(block)
        declared_keys = block.parameters
          .select { |type, _| type == :keyreq || type == :key }
          .map(&:last)
        ->(**kw) { block.call(**kw.slice(*declared_keys)) }
      end
    end
  end
end
