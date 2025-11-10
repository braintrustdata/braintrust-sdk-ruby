# frozen_string_literal: true

require "test_helper"
require "braintrust/trace"
require "braintrust/trace/span_filter"
require "opentelemetry/sdk"

class SpanFilterTest < Minitest::Test
  def test_init_with_filter_ai_spans_keeps_ai_spans
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

    Braintrust.init(
      api_key: "test-key",
      set_global: false,
      blocking_login: false,
      enable_tracing: true,
      tracer_provider: tracer_provider,
      exporter: exporter,
      filter_ai_spans: true
    )

    tracer = tracer_provider.tracer("test")
    tracer.in_span("gen_ai.completion") do
      tracer.in_span("database.query") {}
    end

    spans = exporter.finished_spans
    assert_equal 1, spans.length, "Should only export AI span"
    assert_equal "gen_ai.completion", spans[0].name
  end

  def test_init_with_filter_ai_spans_keeps_braintrust_prefix
    exporter, tracer = setup_with_filter(filter_ai_spans: true)

    tracer.in_span("braintrust.eval") do
      tracer.in_span("http.request") {}
    end

    spans = exporter.finished_spans
    assert_equal 1, spans.length
    assert_equal "braintrust.eval", spans[0].name
  end

  def test_init_with_filter_ai_spans_keeps_llm_prefix
    exporter, tracer = setup_with_filter(filter_ai_spans: true)

    tracer.in_span("llm.chat") do
      tracer.in_span("cache.get") {}
    end

    spans = exporter.finished_spans
    assert_equal 1, spans.length
    assert_equal "llm.chat", spans[0].name
  end

  def test_init_with_filter_ai_spans_keeps_ai_prefix
    exporter, tracer = setup_with_filter(filter_ai_spans: true)

    tracer.in_span("ai.generation") do
      tracer.in_span("filesystem.read") {}
    end

    spans = exporter.finished_spans
    assert_equal 1, spans.length
    assert_equal "ai.generation", spans[0].name
  end

  def test_init_with_filter_ai_spans_keeps_traceloop_prefix
    exporter, tracer = setup_with_filter(filter_ai_spans: true)

    tracer.in_span("traceloop.workflow") do
      tracer.in_span("redis.command") {}
    end

    spans = exporter.finished_spans
    assert_equal 1, spans.length
    assert_equal "traceloop.workflow", spans[0].name
  end

  def test_init_with_filter_ai_spans_keeps_ai_attributes
    exporter, tracer = setup_with_filter(filter_ai_spans: true)

    tracer.in_span("custom.span") do |span|
      span.set_attribute("gen_ai.model", "gpt-4")
      tracer.in_span("other.span") do |child|
        child.set_attribute("http.status", "200")
      end
    end

    spans = exporter.finished_spans
    assert_equal 1, spans.length
    assert_equal "custom.span", spans[0].name
  end

  def test_init_with_filter_ai_spans_ignores_system_attributes
    exporter, tracer = setup_with_filter(filter_ai_spans: true)

    tracer.in_span("gen_ai.root") do
      tracer.in_span("http.request") do |span|
        span.set_attribute("custom.field", "value")
      end
    end

    spans = exporter.finished_spans
    assert_equal 1, spans.length
    assert_equal "gen_ai.root", spans[0].name
  end

  def test_init_with_filter_ai_spans_always_keeps_root_spans
    exporter, tracer = setup_with_filter(filter_ai_spans: true)

    tracer.in_span("database.query") {}

    spans = exporter.finished_spans
    assert_equal 1, spans.length, "Root spans should always be kept"
  end

  def test_init_with_filter_ai_spans_drops_non_root_non_ai_spans
    exporter, tracer = setup_with_filter(filter_ai_spans: true)

    tracer.in_span("gen_ai.completion") do
      tracer.in_span("database.query") {}
    end

    spans = exporter.finished_spans
    assert_equal 1, spans.length
    assert_equal "gen_ai.completion", spans[0].name
  end

  def test_init_with_custom_filter_function
    custom_filter = ->(span) do
      span.name.include?("important") ? 1 : -1
    end

    exporter, tracer = setup_with_filter(span_filter_funcs: [custom_filter])

    tracer.in_span("important.operation") do
      tracer.in_span("regular.operation") {}
    end

    spans = exporter.finished_spans
    assert_equal 1, spans.length
    assert_equal "important.operation", spans[0].name
  end

  def test_init_with_custom_filter_can_drop_spans
    custom_filter = ->(span) do
      span.name.include?("ignore") ? -1 : 0
    end

    exporter, tracer = setup_with_filter(span_filter_funcs: [custom_filter])

    tracer.in_span("good.span") do
      tracer.in_span("ignore.span") {}
    end

    spans = exporter.finished_spans
    assert_equal 1, spans.length
    assert_equal "good.span", spans[0].name
  end

  def test_init_with_multiple_filters_first_wins
    filter1 = ->(span) { span.name.include?("keep") ? 1 : 0 }
    filter2 = ->(span) { span.name.include?("other") ? -1 : 0 }

    exporter, tracer = setup_with_filter(span_filter_funcs: [filter1, filter2])

    tracer.in_span("keep.parent") do
      tracer.in_span("other.span") {}
      tracer.in_span("keep.child") {}
    end

    spans = exporter.finished_spans
    assert_equal 2, spans.length
    span_names = spans.map(&:name).sort
    assert_equal ["keep.child", "keep.parent"], span_names
  end

  def test_init_without_filters_exports_all_spans
    exporter, tracer = setup_with_filter(filter_ai_spans: false)

    tracer.in_span("gen_ai.completion") {}
    tracer.in_span("database.query") {}
    tracer.in_span("http.request") {}

    spans = exporter.finished_spans
    assert_equal 3, spans.length, "Without filters, all spans should be exported"
  end

  def test_init_with_ai_filter_and_custom_filter_both_applied
    custom_filter = ->(span) { span.name.include?("special") ? 1 : 0 }

    exporter, tracer = setup_with_filter(
      filter_ai_spans: true,
      span_filter_funcs: [custom_filter]
    )

    tracer.in_span("gen_ai.root") do
      tracer.in_span("special.operation") {}
      tracer.in_span("database.query") {}
    end

    spans = exporter.finished_spans
    assert_equal 2, spans.length
    span_names = spans.map(&:name).sort
    assert_equal ["gen_ai.root", "special.operation"], span_names
  end

  private

  def setup_with_filter(filter_ai_spans: false, span_filter_funcs: [])
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

    Braintrust.init(
      api_key: "test-key",
      set_global: false,
      blocking_login: false,
      enable_tracing: true,
      tracer_provider: tracer_provider,
      exporter: exporter,
      filter_ai_spans: filter_ai_spans,
      span_filter_funcs: span_filter_funcs
    )

    tracer = tracer_provider.tracer("test")
    [exporter, tracer]
  end
end
