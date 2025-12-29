# frozen_string_literal: true

# Test helpers for RubyLLM integration tests.
# Provides gem loading helpers for the ruby_llm gem.

module Braintrust
  module Contrib
    module RubyLLM
      module IntegrationHelper
        # Skip test unless ruby_llm gem is available.
        # Loads the gem if available.
        def skip_unless_ruby_llm!
          unless Gem.loaded_specs["ruby_llm"]
            skip "ruby_llm gem not available"
          end

          require "ruby_llm" unless defined?(::RubyLLM)
        end

        # Load ruby_llm gem if available (doesn't skip, for tests that handle both states).
        def load_ruby_llm_if_available
          if Gem.loaded_specs["ruby_llm"]
            require "ruby_llm" unless defined?(::RubyLLM)
          end
        end
      end
    end
  end
end
