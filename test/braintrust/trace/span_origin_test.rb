# frozen_string_literal: true

require "test_helper"
require "opentelemetry/sdk"

class Braintrust::Trace::SpanOriginTest < Minitest::Test
  SpanOrigin = Braintrust::Trace::SpanOrigin
  CONTEXT_JSON = "braintrust.context_json"

  # ---------------------------------------------------------------------------
  # Pure unit tests: attributes_with_origin (no OTel involved)
  # ---------------------------------------------------------------------------

  def test_adds_origin_to_empty_attributes
    result = SpanOrigin.attributes_with_origin({}, instrumentation_name: "my-instrumentation", environment: nil)

    origin = span_origin(result)
    assert_equal "braintrust.sdk.ruby", origin["name"]
    assert_equal Braintrust::VERSION, origin["version"]
    assert_equal({"name" => "my-instrumentation"}, origin["instrumentation"])
    refute origin.key?("environment"), "environment should be omitted when nil"
  end

  def test_adds_environment_when_present
    result = SpanOrigin.attributes_with_origin({}, instrumentation_name: "x", environment: {type: "server", name: "prod"})

    assert_equal({"type" => "server", "name" => "prod"}, span_origin(result)["environment"])
  end

  def test_preserves_existing_origin_values_and_merges_unrelated_context_keys
    existing = JSON.generate(
      "metadata" => {"source" => "user"},
      "span_origin" => {
        "name" => "custom.name",
        "environment" => {"type" => "server", "name" => "custom"}
      }
    )

    result = SpanOrigin.attributes_with_origin(
      {CONTEXT_JSON => existing},
      instrumentation_name: "x",
      environment: {type: "local", name: "should-not-override"}
    )

    context = JSON.parse(result[CONTEXT_JSON])
    assert_equal "user", context.dig("metadata", "source"), "unrelated context keys must be preserved"
    assert_equal "custom.name", context.dig("span_origin", "name"), "existing origin values must be preserved"
    assert_equal({"type" => "server", "name" => "custom"}, context.dig("span_origin", "environment"),
      "existing environment must not be overridden by detection")
    assert_equal Braintrust::VERSION, context.dig("span_origin", "version"), "missing fields must be filled in"
  end

  def test_returns_same_attributes_object_when_nothing_changes
    attributes = SpanOrigin.attributes_with_origin({}, instrumentation_name: "x", environment: nil)

    # Second pass: every field already present -> no allocation, same object back.
    again = SpanOrigin.attributes_with_origin(attributes, instrumentation_name: "x", environment: nil)

    assert_same attributes, again
  end

  def test_malformed_context_json_is_treated_as_empty
    result = SpanOrigin.attributes_with_origin({CONTEXT_JSON => "not json{"}, instrumentation_name: "x", environment: nil)

    assert_equal "braintrust.sdk.ruby", span_origin(result)["name"]
  end

  # ---------------------------------------------------------------------------
  # enrich: SpanData mutation semantics
  # ---------------------------------------------------------------------------

  def test_enrich_replaces_attributes_without_mutating_the_shared_hash
    span_data = build_span_data(instrumentation_name: "svc", attributes: {"existing" => "kept"})
    shared_hash = span_data.attributes

    enriched = SpanOrigin.enrich(span_data, environment: nil)

    assert_same span_data, enriched, "enrich mutates and returns the same SpanData"
    assert_equal "kept", enriched.attributes["existing"]
    assert enriched.attributes.key?(CONTEXT_JSON)
    assert_equal enriched.attributes.length, enriched.total_recorded_attributes
    refute shared_hash.key?(CONTEXT_JSON), "the original (shared) attributes hash must not be mutated"
  end

  def test_enrich_uses_the_span_data_instrumentation_scope
    span_data = build_span_data(instrumentation_name: "some.library")

    enriched = SpanOrigin.enrich(span_data, environment: nil)

    assert_equal "some.library", span_origin(enriched.attributes).dig("instrumentation", "name")
  end

  # ---------------------------------------------------------------------------
  # Integration through the Braintrust in-memory exporter (via the rig)
  # ---------------------------------------------------------------------------

  def test_exported_spans_are_decorated_with_span_origin
    rig = setup_otel_test_rig
    tracer = rig.tracer("my-app")

    tracer.start_span("work").finish
    span_data = rig.drain_one

    origin = span_origin(span_data.attributes)
    assert_equal "braintrust.sdk.ruby", origin["name"]
    assert_equal Braintrust::VERSION, origin["version"]
    assert_equal "my-app", origin.dig("instrumentation", "name")
  end

  def test_exported_spans_include_detected_environment
    rig = setup_otel_test_rig
    tracer = rig.tracer("my-app")

    span_data = nil
    ClimateControl.modify(BRAINTRUST_ENVIRONMENT_TYPE: "server", BRAINTRUST_ENVIRONMENT_NAME: "production") do
      tracer.start_span("work").finish
      span_data = rig.drain_one
    end

    assert_equal({"type" => "server", "name" => "production"}, span_origin(span_data.attributes)["environment"])
  end

  # ---------------------------------------------------------------------------
  # Decoration is a behavior of the Braintrust exporter, NOT a global patch:
  # a plain exporter on another provider must never see span origin.
  # ---------------------------------------------------------------------------

  def test_plain_in_memory_exporter_is_not_decorated
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    tracer_provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter))

    tracer_provider.tracer("other").start_span("s").finish
    tracer_provider.force_flush

    refute exporter.finished_spans.first.attributes.key?(CONTEXT_JSON),
      "span origin must not leak onto exporters that do not wear the behavior"
  end

  private

  def span_origin(attributes)
    JSON.parse(attributes.fetch(CONTEXT_JSON)).fetch("span_origin")
  end

  def build_span_data(instrumentation_name:, attributes: {})
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    span = tracer_provider.tracer(instrumentation_name).start_span("s", attributes: attributes)
    span.finish
    span.to_span_data
  end
end
