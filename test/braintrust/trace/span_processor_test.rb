# frozen_string_literal: true

require "test_helper"
require "opentelemetry/sdk"
require "ostruct"

class Braintrust::Trace::SpanProcessorTest < Minitest::Test
  def setup
    @state = get_unit_test_state
  end

  def test_adds_default_parent_if_missing
    # Create a mock wrapped processor
    wrapped = Minitest::Mock.new
    wrapped.expect(:on_start, nil, [Object, Object])

    processor = Braintrust::Trace::SpanProcessor.new(wrapped, @state)

    # Create a span
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    tracer = tracer_provider.tracer("test")
    span = tracer.start_span("test-span")

    # Call on_start (note: OpenTelemetry Ruby passes span first, then context)
    processor.on_start(span, OpenTelemetry::Context.empty)

    # Check that braintrust.parent was added
    attributes = span.attributes
    assert_equal "project_name:test-project", attributes["braintrust.parent"]

    wrapped.verify
  end

  def test_preserves_existing_parent
    # Create a mock wrapped processor
    wrapped = Minitest::Mock.new
    wrapped.expect(:on_start, nil, [Object, Object])

    processor = Braintrust::Trace::SpanProcessor.new(wrapped, @state)

    # Create a span with existing parent
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    tracer = tracer_provider.tracer("test")
    span = tracer.start_span("test-span")
    span.set_attribute("braintrust.parent", "project_name:custom-project")

    # Call on_start (note: OpenTelemetry Ruby passes span first, then context)
    processor.on_start(span, OpenTelemetry::Context.empty)

    # Check that existing parent was preserved
    attributes = span.attributes
    assert_equal "project_name:custom-project", attributes["braintrust.parent"]

    wrapped.verify
  end

  def test_adds_org_attribute
    # Create a mock wrapped processor
    wrapped = Minitest::Mock.new
    wrapped.expect(:on_start, nil, [Object, Object])

    processor = Braintrust::Trace::SpanProcessor.new(wrapped, @state)

    # Create a span
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    tracer = tracer_provider.tracer("test")
    span = tracer.start_span("test-span")

    # Call on_start (note: OpenTelemetry Ruby passes span first, then context)
    processor.on_start(span, OpenTelemetry::Context.empty)

    # Check that org was added
    attributes = span.attributes
    assert_equal "test-org", attributes["braintrust.org"]

    wrapped.verify
  end

  def test_adds_app_url_attribute
    # Create a mock wrapped processor
    wrapped = Minitest::Mock.new
    wrapped.expect(:on_start, nil, [Object, Object])

    processor = Braintrust::Trace::SpanProcessor.new(wrapped, @state)

    # Create a span
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    tracer = tracer_provider.tracer("test")
    span = tracer.start_span("test-span")

    # Call on_start (note: OpenTelemetry Ruby passes span first, then context)
    processor.on_start(span, OpenTelemetry::Context.empty)

    # Check that app_url was added
    attributes = span.attributes
    assert_equal "https://app.example.com", attributes["braintrust.app_url"]

    wrapped.verify
  end

  def test_span_processor_enables_permalink_generation
    # This test verifies that spans processed by SpanProcessor have all attributes needed for permalinks
    # Create a mock wrapped processor
    wrapped = Minitest::Mock.new
    wrapped.expect(:on_start, nil, [Object, Object])

    processor = Braintrust::Trace::SpanProcessor.new(wrapped, @state)

    # Create a span
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    tracer = tracer_provider.tracer("test")
    span = tracer.start_span("test-span")

    # Call on_start to add Braintrust attributes
    processor.on_start(span, OpenTelemetry::Context.empty)

    # Generate permalink - should not be empty since all required attributes are present
    permalink = Braintrust::Trace.permalink(span)

    refute_empty permalink, "Permalink should be generated successfully for processed spans"
    assert_includes permalink, "https://app.example.com/app/test-org/p/test-project/logs"

    wrapped.verify
  end

  def test_inherits_parent_from_parent_span_context
    # Set up otel test rig (includes Braintrust processor and state)
    rig = setup_otel_test_rig

    tracer = rig.tracer("test")

    # Create parent span with experiment_id parent
    # Note: SpanProcessor will add org and app_url automatically
    parent_span = tracer.start_span("parent")
    parent_span.set_attribute("braintrust.parent", "experiment_id:abc-123")

    # Create child span in parent context
    OpenTelemetry::Trace.with_span(parent_span) do
      child_span = tracer.start_span("child")
      child_span.finish
    end

    parent_span.finish

    # Drain spans
    spans = rig.drain
    assert_equal 2, spans.length

    parent_span_data = spans.find { |s| s.name == "parent" }
    child_span_data = spans.find { |s| s.name == "child" }

    # Parent should have experiment_id (explicitly set) plus org and app_url (added by processor)
    assert_equal "experiment_id:abc-123", parent_span_data.attributes["braintrust.parent"]
    assert_equal rig.state.org_name, parent_span_data.attributes["braintrust.org"]
    assert_equal rig.state.app_url, parent_span_data.attributes["braintrust.app_url"]

    # Child should inherit parent from parent span, and get org/app_url from state
    assert_equal "experiment_id:abc-123", child_span_data.attributes["braintrust.parent"]
    assert_equal rig.state.org_name, child_span_data.attributes["braintrust.org"]
    assert_equal rig.state.app_url, child_span_data.attributes["braintrust.app_url"]
  end
end
