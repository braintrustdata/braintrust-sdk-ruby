# frozen_string_literal: true

require "opentelemetry/sdk"

module Test
  module Support
    # In-memory span exporter for tests that wears the same Braintrust exporter
    # behaviors as the production SpanExporter - currently span origin decoration
    # (SpanOrigin), prepended below.
    #
    # Both this prepend and the production SpanExporter call SpanOrigin.enrich_batch,
    # so origin enrichment is shared between the production and test exporters.
    # Tests can therefore assert on origin-decorated SpanData without any network
    # calls or a real OTLP exporter.
    class InMemoryExporter < OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter
      prepend Braintrust::Trace::SpanOrigin
    end
  end
end
