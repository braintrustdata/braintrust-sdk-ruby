# frozen_string_literal: true

require_relative "../integration"

module Braintrust
  module Contrib
    module OpenAI
      # OpenAI integration for automatic instrumentation.
      # Instruments the official openai gem (not ruby-openai).
      class Integration
        include Braintrust::Contrib::Integration

        # @return [Symbol] Unique identifier for this integration
        def self.integration_name
          :openai
        end

        # @return [Array<String>] Gem names this integration supports
        def self.gem_names
          ["openai"]
        end

        # @return [Array<String>] Require paths for auto-instrument detection
        def self.require_paths
          ["openai"]
        end

        # @return [String] Minimum compatible version
        def self.minimum_version
          "0.1.0"
        end

        # Check if the official openai gem is loaded (not ruby-openai).
        # The ruby-openai gem also uses "require 'openai'", so we need to distinguish them.
        # @return [Boolean] true if official openai gem is available
        def self.available?
          # Check if "openai" gem is in loaded specs (official gem name)
          return true if Gem.loaded_specs.key?("openai")

          # Also check $LOADED_FEATURES for files ending with /openai.rb
          # and containing /openai- in the path (gem version in path)
          # This helps distinguish from ruby-openai which has /ruby-openai-/ in path
          $LOADED_FEATURES.any? do |feature|
            feature.end_with?("/openai.rb") && feature.include?("/openai-")
          end
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
