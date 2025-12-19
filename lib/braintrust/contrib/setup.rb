# frozen_string_literal: true

require_relative "../internal/env"

module Braintrust
  module Contrib
    module Setup
      class << self
        def run!
          return if @setup_complete
          @setup_complete = true

          if Internal::Env.auto_instrument
            # Set up deferred patching for libraries loaded later
            if rails_environment?
              setup_rails_hook!
            else
              setup_require_hook!
            end
          end
        end

        def rails_environment?
          # Check for Rails::Railtie which is defined during gem loading,
          # before Rails.application exists
          defined?(::Rails::Railtie)
        end

        def setup_rails_hook!
          require_relative "rails/railtie"
        end

        def setup_require_hook!
          registry = Contrib::Registry.instance
          only = Internal::Env.instrument_only
          except = Internal::Env.instrument_except

          # Store original require
          original_require = Kernel.method(:require)

          Kernel.define_method(:require) do |path|
            result = original_require.call(path)

            # Reentrancy guard
            unless Thread.current[:braintrust_in_require_hook]
              begin
                Thread.current[:braintrust_in_require_hook] = true

                # Check if any integration matches this require path
                registry.integrations_for_require_path(path).each do |integration|
                  next unless integration.available? && integration.compatible?
                  next if only && !only.include?(integration.integration_name)
                  next if except&.include?(integration.integration_name)
                  integration.patch!
                end
              rescue => e
                Braintrust::Log.error("Failed to auto-instrument on `require`: #{e.message}")
              ensure
                Thread.current[:braintrust_in_require_hook] = false
              end
            end

            result
          end
        end
      end
    end
  end
end
