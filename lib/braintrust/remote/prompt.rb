# frozen_string_literal: true

module Braintrust
  module Remote
    # Handles prompt building and formatting
    # This is used by the parameter system to support prompt-based parameters
    class Prompt
      attr_reader :messages, :model, :params

      def initialize(messages: [], model: nil, **params)
        @messages = messages
        @model = model
        @params = params
      end

      # Build a prompt from a hash (typically from Braintrust API)
      def self.from_hash(hash)
        return nil unless hash

        # If already a Prompt, return as-is
        return hash if hash.is_a?(Prompt)

        # Must be a Hash
        unless hash.is_a?(Hash)
          raise ArgumentError, "Expected Hash or Prompt, got #{hash.class}"
        end

        new(
          messages: hash["messages"] || hash[:messages] || [],
          model: hash["model"] || hash[:model],
          **extract_params(hash)
        )
      end

      # Build a prompt from data (used by parameter validation)
      def self.from_data(name, data)
        from_hash(data)
      end

      # Convert to hash for JSON serialization
      def to_h
        {
          messages: @messages,
          model: @model,
          **@params
        }.compact
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      # Allow hash-like access for compatibility
      def [](key)
        to_h[key.to_sym] || to_h[key.to_s]
      end

      class << self
        private

        def extract_params(hash)
          known_keys = %w[messages model]
          hash.reject { |k, _| known_keys.include?(k.to_s) }
            .transform_keys(&:to_sym)
        end
      end
    end
  end
end
