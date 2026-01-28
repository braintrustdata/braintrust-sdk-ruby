# frozen_string_literal: true

# Test helpers for Anthropic integration tests.
# Provides gem loading helpers for the anthropic gem.

module Braintrust
  module Contrib
    module Anthropic
      module IntegrationHelper
        # Skip test unless anthropic gem is available.
        # Loads the gem if available.
        def skip_unless_anthropic!
          unless Gem.loaded_specs["anthropic"]
            skip "anthropic gem not available"
          end

          require "anthropic" unless defined?(::Anthropic)
        end

        # Load anthropic gem if available (doesn't skip, for tests that handle both states).
        def load_anthropic_if_available
          if Gem.loaded_specs["anthropic"]
            require "anthropic" unless defined?(::Anthropic)
          end
        end

        # Skip test unless Beta::Messages is available.
        def skip_unless_beta_messages!
          unless defined?(::Anthropic::Resources::Beta) &&
              defined?(::Anthropic::Resources::Beta::Messages)
            skip "Beta::Messages not available in this SDK version"
          end
        end
      end
    end
  end
end
