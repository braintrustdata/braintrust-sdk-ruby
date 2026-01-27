# frozen_string_literal: true

module Braintrust
  module Internal
    # Environment variable utilities.
    module Env
      ENV_AUTO_INSTRUMENT = "BRAINTRUST_AUTO_INSTRUMENT"
      ENV_INSTRUMENT_EXCEPT = "BRAINTRUST_INSTRUMENT_EXCEPT"
      ENV_INSTRUMENT_ONLY = "BRAINTRUST_INSTRUMENT_ONLY"
      ENV_FLUSH_ON_EXIT = "BRAINTRUST_FLUSH_ON_EXIT"

      def self.auto_instrument
        ENV[ENV_AUTO_INSTRUMENT] != "false"
      end

      # Whether to automatically flush spans on program exit. Default: true
      def self.flush_on_exit
        ENV[ENV_FLUSH_ON_EXIT] != "false"
      end

      def self.instrument_except
        parse_list(ENV_INSTRUMENT_EXCEPT)
      end

      def self.instrument_only
        parse_list(ENV_INSTRUMENT_ONLY)
      end

      # Parse a comma-separated environment variable into an array of symbols.
      # @param key [String] The environment variable name
      # @return [Array<Symbol>, nil] Array of symbols, or nil if not set
      def self.parse_list(key)
        value = ENV[key]
        return nil unless value
        value.split(",").map(&:strip).map(&:to_sym)
      end
    end
  end
end
