# frozen_string_literal: true

module Braintrust
  module Contrib
    # Per-instance or per-class configuration context.
    # Allows attaching generic configuration to specific objects or classes.
    class Context
      # Set or update context on a target object.
      # Creates a new context if one doesn't exist, or updates existing context.
      # @param target [Object] The object to attach context to
      # @param options [Hash] Configuration options to store
      # @return [Context, nil] The existing context if updated, nil if created new or options empty
      def self.set!(target, **options)
        return nil if options.empty?

        if (ctx = from(target))
          # Update existing context
          options.each { |k, v| ctx[k] = v }
        else
          # Create and attach new context
          target.instance_variable_set(:@braintrust_context, new(**options))
        end

        ctx
      end

      # Retrieve context from a target, checking instance then class.
      # @param target [Object] The object to retrieve context from
      # @return [Context, nil] The context if found, nil otherwise
      def self.from(target)
        return nil unless target
        return nil unless target.respond_to?(:instance_variable_get)

        # Check target instance
        ctx = target.instance_variable_get(:@braintrust_context)
        return ctx if ctx

        # Check target class
        target.class.instance_variable_get(:@braintrust_context)
      end

      # @param options [Hash] Configuration options
      def initialize(**options)
        @options = options
      end

      def [](key)
        @options[key]
      end

      def []=(key, value)
        @options[key] = value
      end

      # Get an option value with a default fallback.
      # @param key [Symbol, String] The option key
      # @param default [Object] The default value if key not found
      # @return [Object] The option value, or default if not found
      def fetch(key, default)
        @options.fetch(key, default)
      end
    end
  end
end
