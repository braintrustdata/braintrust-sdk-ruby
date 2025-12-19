# frozen_string_literal: true

# Auto-instrument file for require-time instrumentation.
# Load this file to automatically instrument all available LLM libraries.
#
# Usage:
#   # Gemfile
#   gem "braintrust", require: "braintrust/auto_instrument"
#
#   # Or in code
#   require "braintrust/auto_instrument"
#
# Environment variables:
#   BRAINTRUST_API_KEY - Required for tracing to work
#   BRAINTRUST_AUTO_INSTRUMENT - Set to "false" to disable (default: true)
#   BRAINTRUST_INSTRUMENT_ONLY - Comma-separated whitelist
#   BRAINTRUST_INSTRUMENT_EXCEPT - Comma-separated blacklist

require_relative "../braintrust"

module Braintrust
  module AutoInstrument
    class << self
      def setup!
        return if @setup_complete

        @setup_complete = true

        # Initialize Braintrust (silent failure if no API key)
        begin
          Braintrust.init
        rescue
          nil
        end

        # Set up deferred patching for libraries loaded later
        if rails_environment?
          setup_rails_hook!
        else
          setup_require_hook!
        end
      end

      private

      def rails_environment?
        defined?(Rails) && Rails.respond_to?(:application) && Rails.application
      end

      def setup_rails_hook!
        Rails.application.config.after_initialize do
          Braintrust.auto_instrument!(
            only: Internal::Env.parse_list("BRAINTRUST_INSTRUMENT_ONLY"),
            except: Internal::Env.parse_list("BRAINTRUST_INSTRUMENT_EXCEPT")
          )
        end
      end

      def setup_require_hook!
        registry = Contrib::Registry.instance
        only = Internal::Env.parse_list("BRAINTRUST_INSTRUMENT_ONLY")
        except = Internal::Env.parse_list("BRAINTRUST_INSTRUMENT_EXCEPT")

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

# Auto-setup when required
Braintrust::AutoInstrument.setup!
