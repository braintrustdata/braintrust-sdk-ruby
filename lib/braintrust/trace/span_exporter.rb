# frozen_string_literal: true

require "opentelemetry/exporter/otlp"

module Braintrust
  module Trace
    # Custom OTLP exporter that groups spans by braintrust.parent attribute
    # and sets the x-bt-parent HTTP header per group. This is required for
    # the Braintrust OTLP backend to route spans to the correct experiment/project.
    #
    # Thread safety: BatchSpanProcessor serializes export() calls via its
    # @export_mutex, so @headers mutation here is safe.
    class SpanExporter < OpenTelemetry::Exporter::OTLP::Exporter
      PARENT_ATTR_KEY = SpanProcessor::PARENT_ATTR_KEY
      PARENT_HEADER = "x-bt-parent"

      SUCCESS = OpenTelemetry::SDK::Trace::Export::SUCCESS
      FAILURE = OpenTelemetry::SDK::Trace::Export::FAILURE

      def initialize(endpoint:, api_key:)
        super(endpoint: endpoint, headers: {"Authorization" => "Bearer #{api_key}"})
      end

      def export(span_data, timeout: nil)
        failed = false
        span_data.group_by { |sd| sd.attributes&.[](PARENT_ATTR_KEY) }.each do |parent_value, spans|
          @headers[PARENT_HEADER] = parent_value if parent_value
          failed = true unless super(spans, timeout: timeout) == SUCCESS
        ensure
          @headers.delete(PARENT_HEADER)
        end
        failed ? FAILURE : SUCCESS
      end
    end
  end
end
