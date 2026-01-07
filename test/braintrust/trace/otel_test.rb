# frozen_string_literal: true

require "test_helper"
require "opentelemetry/sdk"

# Tests for OpenTelemetry tracer provider replacement scenarios.
#
# This tests the bug where Braintrust's SpanProcessor gets orphaned when a user
# reconfigures OpenTelemetry after Braintrust.init has been called.
#
# Bug scenario:
# 1. Braintrust.init creates a TracerProvider and attaches SpanProcessor
# 2. User calls OpenTelemetry::SDK.configure (creates NEW provider, replaces global)
# 3. Spans go to NEW provider, which doesn't have Braintrust's processor
# 4. Braintrust's processor is orphaned - spans never reach Braintrust backend
class Braintrust::Trace::OtelTest < Minitest::Test
  def setup
    # Clear global state before each test
    Braintrust::State.global = nil
    # Reset OTel to default state
    reset_otel_provider!
  end

  def teardown
    Braintrust::State.global = nil
    reset_otel_provider!
  end

  # Test the WORKING scenario: OTel configured FIRST, then Braintrust.init
  # Braintrust should reuse the existing provider and add its processor
  def test_otel_configured_before_braintrust_init
    # Step 1: User configures OTel first
    user_exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    OpenTelemetry::SDK.configure do |c|
      c.add_span_processor(
        OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(user_exporter)
      )
    end
    provider_after_otel = OpenTelemetry.tracer_provider

    # Step 2: Call Braintrust.init (should REUSE existing provider)
    state = get_unit_test_state(enable_tracing: true)
    Braintrust::State.global = state

    provider_after_init = OpenTelemetry.tracer_provider

    # Verify same provider is used
    assert_same provider_after_otel, provider_after_init,
      "Braintrust.init should reuse existing SDK TracerProvider"

    # Verify Braintrust processor was added
    processors = provider_after_init.instance_variable_get(:@span_processors)
    braintrust_processor = processors.find { |p| p.is_a?(Braintrust::Trace::SpanProcessor) }
    assert braintrust_processor, "Braintrust::Trace::SpanProcessor should be added to existing provider"

    # Step 3: Create a span
    tracer = OpenTelemetry.tracer_provider.tracer("test")
    tracer.in_span("test-span") do |span|
      span.set_attribute("test.attr", "value")
    end

    # Step 4: Verify span was captured by user's exporter
    # (Braintrust processor wraps the chain, so spans flow through both)
    OpenTelemetry.tracer_provider.force_flush
    spans = user_exporter.finished_spans
    assert_equal 1, spans.length, "Span should be captured"
    assert_equal "test-span", spans.first.name
  end

  # Test the scenario: Braintrust.init FIRST, then OTel reconfigured
  # Braintrust's processor should be automatically re-attached to the new provider
  def test_braintrust_processor_survives_provider_replacement
    # Step 1: Braintrust.init first (creates and sets tracer provider)
    state = get_unit_test_state(enable_tracing: true)
    Braintrust::State.global = state

    original_provider = OpenTelemetry.tracer_provider
    original_processors = original_provider.instance_variable_get(:@span_processors).dup

    # Verify Braintrust processor is on original provider
    braintrust_processor = original_processors.find { |p| p.is_a?(Braintrust::Trace::SpanProcessor) }
    assert braintrust_processor, "Braintrust processor should be on original provider"

    # Step 2: User reconfigures OTel (creates NEW provider, REPLACING global)
    user_exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    OpenTelemetry::SDK.configure do |c|
      c.add_span_processor(
        OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(user_exporter)
      )
    end

    new_provider = OpenTelemetry.tracer_provider

    # Verify providers are different (OTel SDK.configure creates a new one)
    refute_same original_provider, new_provider,
      "OTel SDK.configure should create a new provider"

    # Step 3: Braintrust processor should be automatically re-attached to new provider
    new_processors = new_provider.instance_variable_get(:@span_processors)
    braintrust_on_new = new_processors.find { |p| p.is_a?(Braintrust::Trace::SpanProcessor) }

    assert braintrust_on_new,
      "Braintrust processor should be automatically re-attached to new provider when OTel is reconfigured"

    # Step 4: Create a span on new provider
    tracer = OpenTelemetry.tracer_provider.tracer("test")
    tracer.in_span("test-span-after-reconfig") do |span|
      span.set_attribute("test.attr", "value")
    end

    # Step 5: Verify span was captured by user's exporter
    OpenTelemetry.tracer_provider.force_flush
    user_spans = user_exporter.finished_spans
    assert_equal 1, user_spans.length, "User's exporter should capture the span"
  end

  private

  def reset_otel_provider!
    # Reset to default proxy provider
    # This is a bit hacky but necessary for test isolation
    if defined?(OpenTelemetry) && OpenTelemetry.respond_to?(:tracer_provider=)
      # Create fresh proxy provider
      OpenTelemetry.instance_variable_set(:@tracer_provider, nil)
    end
  end
end
