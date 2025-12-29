# frozen_string_literal: true

require_relative "../integration"

module Braintrust
  module Contrib
    module RubyLLM
      # RubyLLM integration for automatic instrumentation.
      # Instruments the crmne/ruby_llm gem.
      class Integration
        include Braintrust::Contrib::Integration

        MINIMUM_VERSION = "1.8.0"

        GEM_NAMES = ["ruby_llm"].freeze
        REQUIRE_PATHS = ["ruby_llm"].freeze

        # @return [Symbol] Unique identifier for this integration
        def self.integration_name
          :ruby_llm
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

        # @return [Boolean] true if ruby_llm gem is available
        def self.loaded?
          defined?(::RubyLLM::Chat) ? true : false
        end

        # Lazy-load the patcher only when actually patching.
        # This keeps the integration stub lightweight.
        # @return [Array<Class>] The patcher classes
        def self.patchers
          require_relative "patcher"
          [ChatPatcher]
        end
      end
    end
  end
end
