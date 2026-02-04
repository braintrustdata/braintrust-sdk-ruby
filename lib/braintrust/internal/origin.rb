# frozen_string_literal: true

require "json"

module Braintrust
  module Internal
    # Origin provides serialization for source object pointers in Braintrust.
    # Used internally to link spans back to their source records (e.g., dataset rows).
    module Origin
      # Serialize an origin pointer to JSON
      # @param object_type [String] Type of source object (e.g., "dataset", "playground_logs")
      # @param object_id [String] ID of the source object
      # @param id [String] ID of the specific record within the source
      # @param xact_id [String] Transaction ID
      # @param created [String, nil] Creation timestamp
      # @return [String] JSON-serialized origin
      def self.to_json(object_type:, object_id:, id:, xact_id:, created:)
        JSON.dump({
          object_type: object_type,
          object_id: object_id,
          id: id,
          _xact_id: xact_id,
          created: created
        })
      end
    end
  end
end
