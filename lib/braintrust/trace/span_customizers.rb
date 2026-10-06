# frozen_string_literal: true

require_relative "span_export_data"
require_relative "../logger"

module Braintrust
  module Trace
    # Ordered export-time transformations, independent of origin and transport.
    class SpanCustomizers
      # A hook failed. Messages are SDK-generated: they identify the customizer
      # and the kind of failure, never span payloads or the hook's own exception
      # message, either of which may contain sensitive data.
      class Error < StandardError; end

      ID_FIELDS = %i[trace_id span_id parent_span_id].freeze
      private_constant :ID_FIELDS

      def initialize(customizers = nil)
        @customizers = (customizers || []).dup.freeze
        @customizers.each { |customizer| validate!(customizer) }
      end

      # Export middleware: customize the batch, then continue. Fail-closed: if any
      # hook fails, logs and returns FAILURE without passing any of the batch on.
      # @yieldparam span_data [Array<OpenTelemetry::SDK::Trace::SpanData>] customized spans
      # @return [Integer] export result from downstream, or FAILURE
      def call(span_data)
        customized = customize(span_data)
      rescue Error => e
        Log.error("Span customization failed; batch not sent: #{e.message}")
        OpenTelemetry::SDK::Trace::Export::FAILURE
      else
        yield customized
      end

      # Transform the whole batch before the exporter groups or serializes it.
      # Raises Error so the batch can fail without sending.
      def customize(span_data)
        return span_data if @customizers.empty?

        # Hooks may call instrumented clients. Suppress tracing so those spans
        # cannot re-enter the exporter and customize themselves forever.
        OpenTelemetry::Common::Utilities.untraced do
          span_data.map { |span| customize_span(span) }
        end
      end

      private

      # Reject objects without the hook up front, so a misspelled method name
      # fails at registration instead of silently skipping redaction.
      def validate!(customizer)
        return if customizer.respond_to?(:on_span_export)

        raise ArgumentError, "#{label(customizer)} must implement on_span_export"
      end

      def customize_span(span)
        # Snapshot IDs so in-place mutation through to_span_data cannot slip past validation.
        ids = identity(span)
        drops = dropped_counts(span)
        view = nil
        @customizers.each do |customizer|
          view ||= writable_view(span)
          result = invoke(customizer, view)
          span = unwrap(result, customizer)
          raise Error, "#{label(customizer)} changed span IDs; trace_id, span_id and parent_span_id must be preserved" unless identity(span) == ids

          view = (result if result.is_a?(SpanExportData))
        end
        restore_counts(span, drops)
      end

      def invoke(customizer, view)
        customizer.on_span_export(view)
      # Rescue broadly: hook errors must fail the batch, not kill the export thread.
      rescue StandardError, ScriptError, SystemStackError => e
        raise Error, "#{label(customizer)} raised #{e.class}"
      end

      def unwrap(result, customizer)
        span = result.is_a?(SpanExportData) ? result.to_span_data : result
        return span if span.is_a?(OpenTelemetry::SDK::Trace::SpanData)

        raise Error, "#{label(customizer)} returned #{result.class}; hooks must return the span or a replacement SpanData"
      end

      def label(customizer)
        customizer.class.name || customizer.class.inspect
      end

      def identity(span)
        ID_FIELDS.map { |field| span.public_send(field).dup }
      end

      # OTel and replacement spans may carry frozen attributes. Only the hash
      # needs to be writable; values and other nested objects remain shared.
      def writable_view(span)
        span.attributes = span.attributes&.dup || {}
        SpanExportData.new(span)
      end

      # Preserve drops caused by SDK limits; entries a customizer deletes are not drops.
      def dropped_counts(span)
        {
          attributes: dropped(span.total_recorded_attributes, span.attributes),
          events: dropped(span.total_recorded_events, span.events),
          links: dropped(span.total_recorded_links, span.links)
        }
      end

      def restore_counts(span, drops)
        span.total_recorded_attributes = span.attributes&.size.to_i + drops[:attributes]
        span.total_recorded_events = span.events&.size.to_i + drops[:events]
        span.total_recorded_links = span.links&.size.to_i + drops[:links]
        span
      end

      def dropped(total, entries)
        [total.to_i - entries&.size.to_i, 0].max
      end
    end
  end
end
