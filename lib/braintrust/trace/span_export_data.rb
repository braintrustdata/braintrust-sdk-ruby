# frozen_string_literal: true

require "forwardable"
require "opentelemetry/sdk"

module Braintrust
  module Trace
    # Mutable view of completed span data with read-only identity fields.
    # Attribute values and other nested objects are shared, not deep-copied.
    class SpanExportData
      extend Forwardable

      ID_FIELDS = [:trace_id, :span_id, :parent_span_id].freeze
      MUTABLE_FIELDS = (OpenTelemetry::SDK::Trace::SpanData.members - ID_FIELDS).freeze
      private_constant :ID_FIELDS, :MUTABLE_FIELDS

      attr_reader(*ID_FIELDS)
      def_delegators :@span_data, *MUTABLE_FIELDS, *MUTABLE_FIELDS.map { |field| :"#{field}=" }
      def_delegators :@span_data, :hex_trace_id, :hex_span_id, :hex_parent_span_id, :instrumentation_library

      def initialize(span_data)
        @span_data = span_data
        @trace_id = span_data.trace_id.dup.freeze
        @span_id = span_data.span_id.dup.freeze
        @parent_span_id = span_data.parent_span_id.dup.freeze
      end

      # Access the underlying OpenTelemetry representation, e.g. to build a replacement.
      # Replacement IDs are validated by the exporter after each hook.
      def to_span_data
        @span_data
      end
    end
  end
end
