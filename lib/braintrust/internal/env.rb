# frozen_string_literal: true

module Braintrust
  module Internal
    # Environment variable utilities.
    module Env
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
