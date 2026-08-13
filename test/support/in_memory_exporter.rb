# frozen_string_literal: true

require "opentelemetry/sdk"

module Test
  module Support
    # In-memory span exporter for tests that wears the same Braintrust exporter
    # behaviors as the production SpanExporter - currently span origin decoration
    # (SpanOrigin), prepended below.
    #
    # Both this and SpanExporter prepend the *same* SpanOrigin module, so the
    # behavior under test cannot drift between the production and test exporters.
    # Tests can therefore assert on origin-decorated SpanData without any network
    # calls or a real OTLP exporter.
    class InMemoryExporter < OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter
      prepend Braintrust::Trace::SpanOrigin
    end
  end
end
