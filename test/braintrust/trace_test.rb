# frozen_string_literal: true

require "test_helper"
require "opentelemetry/sdk"

class Braintrust::TraceTest < Minitest::Test
  def setup
    # Clear global state before each test
    Braintrust::State.global = nil
  end

  def test_enable_raises_error_if_no_state_available
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

    error = assert_raises(Braintrust::Error) do
      Braintrust::Trace.enable(tracer_provider)
    end

    assert_match(/no state available/i, error.message)
  end

  def test_enable_with_explicit_state
    state = get_test_state
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

    # Should not raise
    Braintrust::Trace.enable(tracer_provider, state: state)

    # Verify that a span processor was registered
    refute_empty tracer_provider.instance_variable_get(:@span_processors)
  end

  def test_enable_with_global_state
    # Set global state
    Braintrust::State.global = get_test_state(api_key: "global-key")

    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

    # Should not raise and use global state
    Braintrust::Trace.enable(tracer_provider)

    # Verify that a span processor was registered
    refute_empty tracer_provider.instance_variable_get(:@span_processors)
  end

  def test_enable_adds_console_exporter_when_env_var_set
    state = get_test_state
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

    # Set env var
    ENV["BRAINTRUST_ENABLE_TRACE_CONSOLE_LOG"] = "true"

    begin
      Braintrust::Trace.enable(tracer_provider, state: state)

      # Should have 2 processors: OTLP + Console
      processors = tracer_provider.instance_variable_get(:@span_processors)
      assert_equal 2, processors.length
    ensure
      # Clean up env var
      ENV.delete("BRAINTRUST_ENABLE_TRACE_CONSOLE_LOG")
    end
  end

  def test_enable_creates_spans_with_braintrust_attributes
    # Set up OpenTelemetry with memory exporter (includes Braintrust processor)
    rig = setup_otel_test_rig

    # Create a span using the tracer helper
    rig.tracer.in_span("test-operation") do |span|
      span.set_attribute("custom.attribute", "custom-value")
    end

    # Drain exactly one span (asserts count and returns the span)
    span = rig.drain_one

    assert_equal "test-operation", span.name
    assert_equal "custom-value", span.attributes["custom.attribute"]

    # Verify Braintrust attributes were added automatically
    assert_equal "project_name:test-project", span.attributes["braintrust.parent"]
    assert_equal "test-org", span.attributes["braintrust.org"]
    assert_equal "https://app.example.com", span.attributes["braintrust.app_url"]
  end

  def test_permalink_with_project_parent
    # Set up OpenTelemetry with memory exporter (includes Braintrust processor)
    rig = setup_otel_test_rig

    # Create a span
    otel_span = nil
    rig.tracer.in_span("test-operation") do |span|
      otel_span = span
    end

    # Generate permalink
    link = Braintrust::Trace.permalink(otel_span)

    # Extract span details
    span_data = rig.drain_one
    trace_id = span_data.hex_trace_id
    span_id = span_data.hex_span_id

    # Verify URL format for project parent
    expected = "https://app.example.com/app/test-org/p/test-project/logs?r=#{trace_id}&s=#{span_id}"
    assert_equal expected, link
  end

  def test_permalink_with_experiment_parent
    # Set up OpenTelemetry with memory exporter (includes Braintrust processor)
    rig = setup_otel_test_rig(default_parent: "experiment_id:test-project/exp-123")

    # Create a span
    otel_span = nil
    rig.tracer.in_span("test-operation") do |span|
      otel_span = span
    end

    # Generate permalink
    link = Braintrust::Trace.permalink(otel_span)

    # Extract span details
    span_data = rig.drain_one
    trace_id = span_data.hex_trace_id
    span_id = span_data.hex_span_id

    # Verify URL format for experiment parent
    expected = "https://app.example.com/app/test-org/p/test-project/experiments/exp-123?r=#{trace_id}&s=#{span_id}"
    assert_equal expected, link
  end

  def test_permalink_with_missing_attributes
    # Set up OpenTelemetry WITHOUT Braintrust processor (to test missing attributes)
    require "opentelemetry/sdk"

    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

    # Add only a simple processor (no Braintrust processor)
    span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
    tracer_provider.add_span_processor(span_processor)

    tracer = tracer_provider.tracer("test")

    # Create a span WITHOUT Braintrust attributes
    otel_span = nil
    tracer.in_span("test-operation") do |span|
      otel_span = span
    end

    # Suppress error logs for this test (we're intentionally testing missing attributes)
    original_level = Braintrust::Log.logger.level
    Braintrust::Log.logger.level = Logger::FATAL

    begin
      # Should return empty string for missing attributes instead of raising
      link = Braintrust::Trace.permalink(otel_span)
      assert_equal "", link
    ensure
      # Restore original log level
      Braintrust::Log.logger.level = original_level
    end
  end

  def test_permalink_with_nil_span
    # Should return empty string for nil span instead of raising
    link = Braintrust::Trace.permalink(nil)
    assert_equal "", link
  end
end
