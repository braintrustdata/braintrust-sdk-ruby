require_relative "braintrust_helper"

module Test
  module Support
    module TracingHelper
      def self.included(base)
        base.include(BraintrustHelper)
      end

      # Sets up OpenTelemetry with an in-memory exporter for testing
      # Returns an OtelTestRig with tracer_provider, exporter, state, and drain() method
      # The exporter can be passed to Braintrust::Trace.enable to replace OTLP exporter
      # @param state_options [Hash] Options to pass to get_unit_test_state
      # @return [OtelTestRig]
      def setup_otel_test_rig(**state_options)
        require "opentelemetry/sdk"

        exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
        tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
        state = get_unit_test_state(**state_options)

        # Add Braintrust span processor (wraps simple processor with memory exporter)
        simple_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
        braintrust_processor = Braintrust::Trace::SpanProcessor.new(simple_processor, state)
        tracer_provider.add_span_processor(braintrust_processor)

        OtelTestRig.new(tracer_provider, exporter, state)
      end

      # Wrapper for OpenTelemetry test setup
      class OtelTestRig
        attr_reader :tracer_provider, :exporter, :state

        def initialize(tracer_provider, exporter, state)
          @tracer_provider = tracer_provider
          @exporter = exporter
          @state = state
        end

        # Get a tracer from the provider
        # @param name [String] tracer name (default: "test")
        # @return [OpenTelemetry::Trace::Tracer]
        def tracer(name = "test")
          @tracer_provider.tracer(name)
        end

        # Flush and drain all spans from the exporter
        # @return [Array<OpenTelemetry::SDK::Trace::SpanData>]
        def drain
          @tracer_provider.force_flush
          spans = @exporter.finished_spans
          @exporter.reset
          spans
        end

        # Flush and drain exactly one span from the exporter
        # Asserts that exactly one span was flushed
        # @return [OpenTelemetry::SDK::Trace::SpanData]
        def drain_one
          spans = drain
          raise Minitest::Assertion, "Expected exactly 1 span, got #{spans.length}" unless spans.length == 1
          spans.first
        end
      end
    end
  end
end
