# frozen_string_literal: true

require "opentelemetry/exporter/otlp"
require_relative "../state"
require_relative "span_origin"
require_relative "span_customizers"
require_relative "../logger"

module Braintrust
  module Trace
    # Custom OTLP exporter for the Braintrust backend. On export it:
    # - stamps span origin provenance onto each SpanData
    # - runs optional customizers through a mutable view with read-only IDs
    # - groups spans by braintrust.parent and sets the x-bt-parent header per group,
    #   so the backend routes them to the correct experiment/project
    #
    # Thread safety: BatchSpanProcessor serializes export() calls via its
    # @export_mutex, so @headers mutation here is safe.
    class SpanExporter < OpenTelemetry::Exporter::OTLP::Exporter
      PARENT_ATTR_KEY = SpanProcessor::PARENT_ATTR_KEY
      PARENT_HEADER = "x-bt-parent"

      SUCCESS = OpenTelemetry::SDK::Trace::Export::SUCCESS
      FAILURE = OpenTelemetry::SDK::Trace::Export::FAILURE

      def initialize(endpoint:, api_key:, span_customizers: nil)
        raise State::MissingAPIKeyError, "api_key is required" if api_key.nil? || api_key.empty?

        @span_customizers = SpanCustomizers.new(span_customizers)

        super(endpoint: endpoint, headers: {"Authorization" => "Bearer #{api_key}"})
      end

      def export(span_data, timeout: nil)
        return FAILURE if @shutdown && !@span_customizers.empty?

        groups = prepare_groups(span_data)
        return FAILURE unless groups

        failed = false
        groups.each do |parent_value, payload|
          @headers[PARENT_HEADER] = parent_value if parent_value
          result = if @span_customizers.empty?
            super(payload, timeout: timeout)
          else
            send_bytes(payload, timeout: timeout)
          end
          failed = true unless result == SUCCESS
        ensure
          @headers.delete(PARENT_HEADER)
        end
        failed ? FAILURE : SUCCESS
      end

      private

      def prepare_groups(span_data)
        # Compose preparation explicitly so origin, hook, and serialization
        # failures stay inside the same fail-closed boundary.
        span_data = SpanOrigin.enrich_batch(span_data)
        span_data = @span_customizers.customize(span_data)
        groups = span_data.group_by { |span| span.attributes&.[](PARENT_ATTR_KEY) }
        return groups if @span_customizers.empty?

        # Validate serialization for the entire customized batch before sending
        # any destination group. Transport retries reuse these encoded bytes.
        groups.transform_values do |spans|
          encode(spans) || raise(TypeError, "Customized spans must be OTLP serializable")
        end
      # Hook errors must not kill the BatchSpanProcessor worker thread.
      rescue StandardError, ScriptError, SystemStackError => e
        raise if @span_customizers.empty?

        Log.error("Failed to prepare customized spans for export: #{e.class}")
        nil
      end
    end
  end
end
