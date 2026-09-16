# frozen_string_literal: true

module Braintrust
  module Internal
    # Origin builds source object pointers, which link spans back to the record
    # they came from (e.g., a dataset row). Pointers stay Hashes internally and
    # are serialized once at the boundary that needs them, so that inbound
    # pointers from the wire and ones we build here have the same shape.
    module Origin
      # Build an origin pointer
      # @param object_type [String] Type of source object (e.g., "dataset", "playground_logs")
      # @param object_id [String] ID of the source object
      # @param id [String] ID of the specific record within the source
      # @param xact_id [String] Transaction ID
      # @param created [String, nil] Creation timestamp
      # @return [Hash] Origin pointer with string keys, matching the wire format
      def self.build(object_type:, object_id:, id:, xact_id:, created:)
        {
          "object_type" => object_type,
          "object_id" => object_id,
          "id" => id,
          "_xact_id" => xact_id,
          "created" => created
        }
      end
    end
  end
end
