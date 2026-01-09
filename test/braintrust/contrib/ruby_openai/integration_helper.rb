# frozen_string_literal: true

# Test helpers for ruby-openai integration tests.
# Provides gem loading helpers that handle the ruby-openai gem vs official openai disambiguation.

module Braintrust
  module Contrib
    module RubyOpenAI
      module IntegrationHelper
        # Skip test unless ruby-openai gem is available (not official openai).
        # Loads the gem if available.
        def skip_unless_ruby_openai!
          if Gem.loaded_specs["openai"]
            skip "ruby-openai gem not available (found official openai gem instead)"
          end

          unless Gem.loaded_specs["ruby-openai"]
            skip "ruby-openai gem not available"
          end

          require "openai" unless defined?(::OpenAI)
        end

        # Load ruby-openai gem if available (doesn't skip, for tests that handle both states).
        def load_ruby_openai_if_available
          if Gem.loaded_specs["ruby-openai"] && !Gem.loaded_specs["openai"]
            require "openai" unless defined?(::OpenAI)
          end
        end
      end
    end
  end
end
