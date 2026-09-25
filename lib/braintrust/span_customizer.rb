# frozen_string_literal: true

module Braintrust
  # Optional synchronous hooks that transform outgoing telemetry, not live spans.
  # Subclass this class or supply any object implementing the desired hooks.
  class SpanCustomizer
    # Transform completed span data through a mutable view with read-only IDs.
    # Return this view or a replacement SpanData, never nil. Nested objects are
    # shared; prefer replacing attribute values over mutating them in place.
    # Exceptions fail the entire batch but do not roll back mutations.
    #
    # @param span [Braintrust::Trace::SpanExportData]
    # @return [Braintrust::Trace::SpanExportData, OpenTelemetry::SDK::Trace::SpanData]
    def on_span_export(span)
      span
    end
  end
end
