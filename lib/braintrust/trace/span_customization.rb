# frozen_string_literal: true

require_relative "span_customizers"
require_relative "../logger"

module Braintrust
  module Trace
    # Span customizer behavior for exporters.
    #
    # Prepend it onto any exporter whose +export(span_data, timeout:)+ it can
    # +super+ into, and the exporter accepts a +span_customizers:+ option on
    # construction and runs those customizers on every export. Prepend it
    # before SpanOrigin, so SpanOrigin runs first and hooks see origin-enriched
    # data:
    #
    #   prepend SpanCustomization
    #   prepend SpanOrigin
    #
    # Customization is fail-closed: if any hook fails, none of the batch is
    # passed on to the wrapped exporter.
    module SpanCustomization
      # Consumes +span_customizers:+ and forwards everything else to the exporter.
      def initialize(*args, span_customizers: nil, **options, &block)
        @span_customizers = SpanCustomizers.new(span_customizers)
        super(*args, **options, &block)
      end

      def export(span_data, timeout: nil)
        super(span_customizers.customize(span_data), timeout: timeout)
      rescue SpanCustomizers::Error => e
        Log.error("Span customization failed; batch not sent: #{e.message}")
        OpenTelemetry::SDK::Trace::Export::FAILURE
      end

      private

      attr_reader :span_customizers
    end
  end
end
