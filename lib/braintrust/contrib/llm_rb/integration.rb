# frozen_string_literal: true

require_relative "../integration"

module Braintrust
  module Contrib
    module LlmRb
      # llm.rb integration for automatic instrumentation.
      # Instruments the 0x-r/llm.rb gem (gem name: "llm.rb").
      class Integration
        include Braintrust::Contrib::Integration

        MINIMUM_VERSION = "4.11.0"

        GEM_NAMES = ["llm.rb"].freeze
        REQUIRE_PATHS = ["llm"].freeze

        # @return [Symbol] Unique identifier for this integration
        def self.integration_name
          :llm_rb
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

        # @return [Boolean] true if llm.rb gem is available
        def self.loaded?
          defined?(::LLM::Context) ? true : false
        end

        # Lazy-load the patcher only when actually patching.
        # @return [Array<Class>] The patcher classes
        def self.patchers
          require_relative "patcher"
          [ContextPatcher]
        end
      end
    end
  end
end
