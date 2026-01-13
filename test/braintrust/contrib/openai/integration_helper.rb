# frozen_string_literal: true

# Test helpers for OpenAI integration tests.
# Provides gem loading helpers that handle the official openai gem vs ruby-openai disambiguation.

module Braintrust
  module Contrib
    module OpenAI
      module IntegrationHelper
        # Skip test unless official openai gem is available (not ruby-openai).
        # Loads the gem if available.
        def skip_unless_openai!
          if Gem.loaded_specs["ruby-openai"]
            skip "openai gem not available (found ruby-openai gem instead)"
          end

          unless Gem.loaded_specs["openai"]
            skip "openai gem not available"
          end

          require "openai" unless defined?(::OpenAI)
        end

        # Load official openai gem if available (doesn't skip, for tests that handle both states).
        def load_openai_if_available
          if Gem.loaded_specs["openai"] && !Gem.loaded_specs["ruby-openai"]
            require "openai" unless defined?(::OpenAI)
          end
        end
      end
    end
  end
end
