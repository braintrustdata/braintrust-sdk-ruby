# frozen_string_literal: true

require_relative "../integration"

module Braintrust
  module Contrib
    module RubyOpenAI
      # RubyOpenAI integration for automatic instrumentation.
      # Instruments the alexrudall ruby-openai gem (not the official openai gem).
      class Integration
        include Braintrust::Contrib::Integration

        MINIMUM_VERSION = "7.0.0"

        GEM_NAMES = ["ruby-openai"].freeze
        REQUIRE_PATHS = ["openai"].freeze

        # @return [Symbol] Unique identifier for this integration
        def self.integration_name
          :ruby_openai
        end

        # @return [Array<String>] Gem names this integration supports
        def self.gem_names
          GEM_NAMES
        end

        # @return [Array<String>] Require paths for auto-instrument detection
        def self.require_paths
          REQUIRE_PATHS
        end

        # @return [String] Minimum compatible version
        def self.minimum_version
          MINIMUM_VERSION
        end

        # @return [Boolean] true if ruby-openai gem is available (not official openai gem)
        def self.loaded?
          # Check if ruby-openai gem is loaded (not the official openai gem).
          # Both gems use "require 'openai'", so we need to distinguish them.
          #
          # OpenAI::Internal is defined ONLY in the official OpenAI gem
          (defined?(::OpenAI::Client) && !defined?(::OpenAI::Internal)) ? true : false
        end

        # Lazy-load the patcher only when actually patching.
        # This keeps the integration stub lightweight.
        # @return [Array<Class>] The patcher classes
        def self.patchers
          require_relative "patcher"
          [ChatPatcher, ResponsesPatcher]
        end
      end
    end
  end
end
