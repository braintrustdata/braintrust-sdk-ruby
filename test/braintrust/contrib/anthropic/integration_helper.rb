# frozen_string_literal: true

# Test helpers for Anthropic integration tests.
# Provides gem loading helpers for the anthropic gem.

module Braintrust
  module Contrib
    module Anthropic
      module IntegrationHelper
        # Model the cassette-backed tests request by default. When it's retired,
        # bump it and re-record each cassette version folder under its appraisal.
        DEFAULT_MODEL = "claude-sonnet-5-5"

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

        # Cassette path for an anthropic interaction, for the loaded anthropic version.
        def anthropic_cassette(name)
          versioned_cassette("anthropic", name)
        end
      end
    end
  end
end
