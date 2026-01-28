# frozen_string_literal: true

require_relative "../integration"

module Braintrust
  module Contrib
    module Anthropic
      # Anthropic integration for automatic instrumentation.
      # Instruments the anthropic gem (https://github.com/anthropics/anthropic-sdk-ruby).
      class Integration
        include Braintrust::Contrib::Integration

        MINIMUM_VERSION = "0.3.0"

        GEM_NAMES = ["anthropic"].freeze
        REQUIRE_PATHS = ["anthropic"].freeze

        # @return [Symbol] Unique identifier for this integration
        def self.integration_name
          :anthropic
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

        # @return [Boolean] true if anthropic gem is available
        def self.loaded?
          defined?(::Anthropic::Client) ? true : false
        end

        # Lazy-load the patchers only when actually patching.
        # This keeps the integration stub lightweight.
        # @return [Array<Class>] The patcher classes
        def self.patchers
          require_relative "patcher"
          [MessagesPatcher, BetaMessagesPatcher]
        end
      end
    end
  end
end
