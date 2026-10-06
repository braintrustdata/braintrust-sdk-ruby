# frozen_string_literal: true

require_relative "../integration"

module Braintrust
  module Contrib
    module Roast
      # Roast workflow and cog instrumentation.
      class Integration
        include Braintrust::Contrib::Integration

        GEM_NAMES = ["roast-ai"].freeze
        REQUIRE_PATHS = ["roast"].freeze
        MINIMUM_VERSION = "1.0.0"

        def self.integration_name = :roast
        def self.gem_names = GEM_NAMES
        def self.require_paths = REQUIRE_PATHS
        def self.minimum_version = MINIMUM_VERSION

        def self.loaded?
          (defined?(::Roast::Workflow) && defined?(::Roast::Cog)) ? true : false
        end

        def self.patchers
          require_relative "patcher"
          [WorkflowPatcher, CogPatcher]
        end
      end
    end
  end
end
