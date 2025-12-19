# frozen_string_literal: true

# Setup file for automatic SDK initialization and instrumentation.
# Load this file to automatically initialize Braintrust and instrument all available LLM libraries.
#
# Usage:
#   # Gemfile
#   gem "braintrust", require: "braintrust/setup"
#
#   # Or in code
#   require "braintrust/setup"
#
# Environment variables:
#   BRAINTRUST_API_KEY - Required for tracing to work
#   BRAINTRUST_AUTO_INSTRUMENT - Set to "false" to disable (default: true)
#   BRAINTRUST_INSTRUMENT_ONLY - Comma-separated whitelist
#   BRAINTRUST_INSTRUMENT_EXCEPT - Comma-separated blacklist

require_relative "../braintrust"
require_relative "contrib/setup"

module Braintrust
  module Setup
    class << self
      def run!
        return if @setup_complete

        @setup_complete = true

        # Initialize Braintrust (silent failure if no API key)
        begin
          Braintrust.init
        rescue => e
          Braintrust::Log.error("Failed to automatically setup Braintrust: #{e.message}")
        end

        # Setup contrib for 3rd party integrations
        Contrib::Setup.run!
      end
    end
  end
end

# Auto-setup when required
Braintrust::Setup.run!
