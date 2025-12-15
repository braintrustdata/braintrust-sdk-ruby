# frozen_string_literal: true

module Braintrust
  module Contrib
    # Base module defining the integration contract.
    # Include this module in integration classes to define the schema.
    # Delegates actual patching to a Patcher subclass.
    module Integration
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Unique symbol name for this integration (e.g., :openai, :anthropic).
        # @return [Symbol]
        def integration_name
          raise NotImplementedError, "#{self} must implement integration_name"
        end

        # Array of gem names this integration supports.
        # @return [Array<String>]
        def gem_names
          raise NotImplementedError, "#{self} must implement gem_names"
        end

        # Require paths for auto-instrument detection.
        # Default implementation returns gem_names.
        # @return [Array<String>]
        def require_paths
          gem_names
        end

        # Is the target library loaded?
        # @return [Boolean]
        def available?
          gem_names.any? { |name| Gem.loaded_specs.key?(name) }
        end

        # Minimum compatible version (optional, inclusive).
        # @return [String, nil]
        def minimum_version
          nil
        end

        # Maximum compatible version (optional, inclusive).
        # @return [String, nil]
        def maximum_version
          nil
        end

        # Is the library version compatible?
        # @return [Boolean]
        def compatible?
          return false unless available?

          gem_names.each do |name|
            spec = Gem.loaded_specs[name]
            next unless spec

            version = spec.version
            return false if minimum_version && version < Gem::Version.new(minimum_version)
            return false if maximum_version && version > Gem::Version.new(maximum_version)
            return true
          end
          false
        end

        # Array of patcher classes for this integration.
        # Override to return multiple patchers for version-specific logic.
        # @return [Array<Class>] Array of patcher classes
        def patchers
          [patcher] # Default: single patcher
        end

        # Convenience method for single patcher (existing pattern).
        # Override this OR patchers (not both).
        # @return [Class] The patcher class
        def patcher
          raise NotImplementedError, "#{self} must implement patcher or patchers"
        end

        # Instrument this integration with optional configuration.
        # If a target is provided, configures the target instance specifically.
        # Otherwise, applies class-level instrumentation to all instances.
        #
        # @param options [Hash] Configuration options
        # @option options [Object] :target Optional target instance to instrument
        # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
        # @return [Boolean] true if patching succeeded or was already done
        #
        # @example Class-level instrumentation (all clients)
        #   integration.instrument!(tracer_provider: my_provider)
        #
        # @example Instance-level instrumentation (specific client)
        #   integration.instrument!(target: client, tracer_provider: my_provider)
        def instrument!(**options)
          if options[:target]
            # Configure the target with provided options
            options = options.dup
            target = options.delete(:target)

            Contrib::Context.set!(target, **options)
          end

          patch!(**options)
        end

        # Apply instrumentation (idempotent). Tries all applicable patchers.
        # This method is typically called by instrument! after configuration.
        #
        # @param options [Hash] Configuration options
        # @option options [Object] :target Optional target instance to patch
        # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
        # @return [Boolean] true if any patching succeeded or was already done
        def patch!(**options)
          return false unless available? && compatible?

          # Try all applicable patchers
          success = false
          patchers.each do |patch|
            # Check if this patcher is applicable
            next unless patch.applicable?

            # Attempt to patch (patcher checks applicable? again under lock)
            success = true if patch.patch!(**options)
          end

          Braintrust::Log.debug("No applicable patcher found for #{integration_name}") unless success
          success
        end

        # Register this integration with the global registry.
        def register!
          Registry.instance.register(self)
        end
      end
    end
  end
end
