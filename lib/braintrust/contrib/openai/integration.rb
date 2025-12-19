# frozen_string_literal: true

require_relative "../integration"
require_relative "deprecated"

module Braintrust
  module Contrib
    module OpenAI
      # OpenAI integration for automatic instrumentation.
      # Instruments the official openai gem (not ruby-openai).
      class Integration
        include Braintrust::Contrib::Integration

        MINIMUM_VERSION = "0.1.0"

        GEM_NAMES = ["openai"].freeze
        REQUIRE_PATHS = ["openai"].freeze

        # @return [Symbol] Unique identifier for this integration
        def self.integration_name
          :openai
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

        # @return [Boolean] true if official openai gem is available
        def self.loaded?
          # Check if the official openai gem is loaded (not ruby-openai).
          # The ruby-openai gem also uses "require 'openai'", so we need to distinguish them.

          # This module is defined ONLY in the official OpenAI gem
          defined?(::OpenAI::Internal) ? true : false
        end

        # Lazy-load the patcher only when actually patching.
        # This keeps the integration stub lightweight.
        # @return [Class] The patcher class
        def self.patchers
          require_relative "patcher"
          [ChatPatcher, ResponsesPatcher]
        end
      end
    end
  end
end
