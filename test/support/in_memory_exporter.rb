# frozen_string_literal: true

require "opentelemetry/sdk"

module Test
  module Support
    # In-memory span exporter for tests
    #
    # It uses the same default export middleware as SpanExporter, so the
    # behavior under test cannot drift between the production and test exporters.
    class InMemoryExporter < OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter
      prepend Braintrust::Trace::ExportMiddleware

      middleware.add(Braintrust::Trace::SpanOrigin)
    end
  end
end
