# frozen_string_literal: true

# Test helpers for llm.rb integration tests.
module Braintrust
  module Contrib
    module LlmRb
      module IntegrationHelper
        # Skip test unless llm.rb gem is available.
        def skip_unless_llm_rb!
          unless Gem.loaded_specs["llm.rb"]
            skip "llm.rb gem not available"
          end

          require "llm" unless defined?(::LLM)
        end
      end
    end
  end
end
