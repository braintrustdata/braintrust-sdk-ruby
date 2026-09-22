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

        # Configures RubyLLM for cassette playback.
        #
        # RubyLLM.configure is global, so every cassette-backed test must call this
        # rather than relying on whichever test happened to configure it first.
        def configure_ruby_llm_for_vcr
          ::RubyLLM.configure do |config|
            config.openai_api_key = get_openai_key
          end
        end

        # Major version of the loaded ruby_llm gem.
        def ruby_llm_major
          Gem.loaded_specs["ruby_llm"]&.version&.segments&.first || 1
        end

        # Cassette path for a ruby_llm interaction.
        #
        # Breaking wire changes land on majors: 2.0 moved the OpenAI provider from
        # Chat Completions to the Responses API. Recording per major means each
        # version replays the endpoint it actually calls, and versions that share a
        # wire format share a recording. A new major needs its own cassettes, which
        # are recorded by running its appraisal with a real OPENAI_API_KEY.
        def ruby_llm_cassette(name)
          "contrib/ruby_llm/v#{ruby_llm_major}/#{name}"
        end
      end
    end
  end
end
