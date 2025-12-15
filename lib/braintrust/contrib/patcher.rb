# frozen_string_literal: true

module Braintrust
  module Contrib
    # Base class for all patchers.
    # Provides thread-safe, idempotent patching with error handling.
    class Patcher
      # For thread-safety, a mutex is used to wrap patching.
      # Each instance of Patcher should have its own copy of the mutex.,
      # allowing each Patcher to work in parallel while protecting the
      # critical patch section.
      @patch_mutex = Mutex.new

      def self.inherited(subclass)
        subclass.instance_variable_set(:@patch_mutex, Mutex.new)
      end

      class << self
        # Has this patcher already been applied?
        # @return [Boolean]
        def patched?(**options)
          @patched == true
        end

        # Override in subclasses to check if patcher should apply.
        # Called after patcher loads but before perform_patch.
        # @return [Boolean] true if this patcher should be applied
        def applicable?
          true # Default: always applicable
        end

        # Apply the patch (thread-safe and idempotent).
        # @param options [Hash] Configuration options passed from integration
        # @option options [Object] :target Optional target instance to patch
        # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
        # @return [Boolean] true if patching succeeded or was already done
        def patch!(**options)
          return false unless applicable?
          return true if patched?(**options) # Fast path

          @patch_mutex.synchronize do
            unless applicable?
              Braintrust::Log.debug("Skipping #{name} - not applicable")
              return false
            end
            return true if patched?(**options) # Double-check under lock

            perform_patch(**options)
            @patched = true
          end
          Braintrust::Log.debug("Patched #{name}")
          true
        rescue => e
          Braintrust::Log.error("Failed to patch #{name}: #{e.message}")
          false
        end

        # Subclasses implement this to perform the actual patching.
        # This method is called under lock after applicable? returns true.
        #
        # @param options [Hash] Configuration options passed from integration
        # @option options [Object] :target Optional target instance to patch
        # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
        # @return [void]
        def perform_patch(**options)
          raise NotImplementedError, "#{self} must implement perform_patch"
        end

        # Reset patched state (primarily for testing).
        def reset!
          @patched = false
        end
      end
    end
  end
end
