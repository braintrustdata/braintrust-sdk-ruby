# frozen_string_literal: true

# Test helpers for Rails integration tests.
# Provides gem loading helpers for Rails railtie testing.

module Braintrust
  module Contrib
    module Rails
      module IntegrationHelper
        # Skip test unless Rails gem is available.
        # Loads the gem if available.
        def skip_unless_rails!
          unless Gem.loaded_specs["rails"] || Gem.loaded_specs["railties"]
            skip "Rails gem not available"
          end

          unless defined?(::Rails::Railtie)
            require "active_support"
            require "rails/railtie"
          end
        end
      end
    end
  end
end
