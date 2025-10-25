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
    rig = setup_otel_test_rig

    # Create a span with explicit experiment parent attribute
    # Experiment parents come from evals, not from default_project
    otel_span = nil
    rig.tracer.in_span("test-operation") do |span|
      span.set_attribute("braintrust.parent", "experiment_id:test-project/exp-123")
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

  def test_permalink_with_nil_span
    link = Braintrust::Trace.permalink(nil)
    assert_equal "", link
  end

  def test_permalink_with_invalid_parent_formats
    original_level = Braintrust::Log.logger.level
    Braintrust::Log.logger.level = Logger::FATAL

    begin
      rig = setup_otel_test_rig

      span_invalid_parent = nil
      rig.tracer.in_span("test-operation") do |span|
        span.set_attribute("braintrust.parent", "invalid-no-colon")
        span_invalid_parent = span
      end

      span_invalid_experiment = nil
      rig.tracer.in_span("test-operation") do |span|
        span.set_attribute("braintrust.parent", "experiment_id:no-slash")
        span_invalid_experiment = span
      end

      [
        ["invalid parent format", span_invalid_parent],
        ["invalid experiment parent", span_invalid_experiment]
      ].each do |description, span|
        link = Braintrust::Trace.permalink(span)
        assert_equal "", link, "Expected empty string for: #{description}"
      end
    ensure
      Braintrust::Log.logger.level = original_level
    end
  end
end
