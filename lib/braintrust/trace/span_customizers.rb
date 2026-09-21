# frozen_string_literal: true

require_relative "span_export_data"

module Braintrust
  module Trace
    # Ordered export-time transformations, independent of origin and transport.
    class SpanCustomizers
      def initialize(customizers = nil)
        @customizers = (customizers || []).dup.freeze
      end

      def empty?
        @customizers.empty?
      end

      # Transform the whole batch before the exporter groups or serializes it.
      # Errors propagate to the exporter so it can fail the batch without sending.
      def customize(span_data)
        return span_data if empty?

        # Hooks may call instrumented clients. Suppress tracing so those spans
        # cannot re-enter the exporter and customize themselves forever.
        OpenTelemetry::Common::Utilities.untraced do
          span_data.map { |span| customize_span(span) }
        end
      end

      private

      def customize_span(span)
        # Snapshot IDs so in-place mutation through to_span_data cannot slip past validation.
        trace_id = span.trace_id.dup.freeze
        span_id = span.span_id.dup.freeze
        parent_span_id = span.parent_span_id.dup.freeze
        # Preserve drops caused by SDK limits; entries a customizer deletes are not drops.
        dropped_attributes = dropped(span.total_recorded_attributes, span.attributes)
        dropped_events = dropped(span.total_recorded_events, span.events)
        dropped_links = dropped(span.total_recorded_links, span.links)
        view = nil
        @customizers.each do |customizer|
          next unless customizer.respond_to?(:on_span_export)
          view ||= writable_view(span)

          result = customizer.on_span_export(view)
          span = result.is_a?(SpanExportData) ? result.to_span_data : result
          unless span.is_a?(OpenTelemetry::SDK::Trace::SpanData)
            raise TypeError, "SpanCustomizer#on_span_export must return SpanExportData or SpanData"
          end
          unless span.trace_id == trace_id && span.span_id == span_id && span.parent_span_id == parent_span_id
            raise ArgumentError, "SpanCustomizer#on_span_export must preserve trace, span and parent IDs"
          end
          view = result.is_a?(SpanExportData) ? result : nil
        end
        span.total_recorded_attributes = span.attributes&.size.to_i + dropped_attributes
        span.total_recorded_events = span.events&.size.to_i + dropped_events
        span.total_recorded_links = span.links&.size.to_i + dropped_links
        span
      end

      # OTel and replacement spans may carry frozen attributes. Only the hash
      # needs to be writable; values and other nested objects remain shared.
      def writable_view(span)
        span.attributes = span.attributes&.dup || {}
        SpanExportData.new(span)
      end

      def dropped(total, entries)
        [total.to_i - entries&.size.to_i, 0].max
      end
    end
  end
end
