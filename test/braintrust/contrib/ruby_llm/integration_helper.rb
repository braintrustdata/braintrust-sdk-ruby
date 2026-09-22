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

        # True when the OpenAI provider talks the Responses API, which ruby_llm 2.0
        # made the default. 1.x only ever spoke Chat Completions.
        def ruby_llm_responses_api?
          version = Gem.loaded_specs["ruby_llm"]&.version
          !version.nil? && version >= Gem::Version.new("2.0.0")
        end

        # Cassette path for a ruby_llm interaction.
        #
        # 1.x and 2.0 hit different endpoints with different payloads, so each
        # protocol gets its own recording rather than one being replayed for both.
        def ruby_llm_cassette(name)
          ruby_llm_responses_api? ? "contrib/ruby_llm/responses/#{name}" : "contrib/ruby_llm/#{name}"
        end
      end
    end
  end
end
