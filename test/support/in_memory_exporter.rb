# frozen_string_literal: true

require "opentelemetry/sdk"

module Test
  module Support
    # In-memory span exporter for tests
    #
    # It prepends the same modules as SpanExporter, so the behavior
    # under test cannot drift between the production and test exporters.
    class InMemoryExporter < OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter
      # The last prepended runs first: origin, then customization.
      prepend Braintrust::Trace::SpanCustomization
      prepend Braintrust::Trace::SpanOrigin
    end
  end
end
