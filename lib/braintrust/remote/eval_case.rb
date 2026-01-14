# frozen_string_literal: true

module Braintrust
  module Remote
    # Represents a single evaluation case with input, expected output, and metadata
    # Extended from standard Eval::Case to support dataset row tracking
    class EvalCase
      attr_reader :input, :expected, :metadata, :id, :created, :tags

      def initialize(input:, expected: nil, metadata: nil, id: nil, created: nil, tags: nil)
        @input = input
        @expected = expected
        @metadata = metadata || {}
        @id = id
        @created = created
        @tags = tags
      end

      # Create an EvalCase from a hash (typically from dataset row)
      # @param hash [Hash] Hash with :input, :expected, :metadata, :id, :created keys
      # @return [EvalCase]
      def self.from_hash(hash)
        hash = hash.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }

        # Preserve _xact_id in metadata if present (Python includes this in origin)
        metadata = hash[:metadata] || {}
        if hash[:_xact_id]
          metadata = metadata.merge("_xact_id" => hash[:_xact_id])
        end

        new(
          input: hash[:input],
          expected: hash[:expected],
          metadata: metadata,
          id: hash[:id],
          created: hash[:created],
          tags: hash[:tags]
        )
      end

      def to_h
        {
          input: @input,
          expected: @expected,
          metadata: @metadata,
          id: @id,
          created: @created,
          tags: @tags
        }.compact
      end
    end
  end
end
