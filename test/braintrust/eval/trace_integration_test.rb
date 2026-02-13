# frozen_string_literal: true

require "test_helper"
require "braintrust"

# Integration tests for trace context feature
class Braintrust::Eval::TraceIntegrationTest < Minitest::Test
  def setup
    @state = Braintrust::State.new(
      api_key: "test-api-key",
      org_id: "test-org-id",
      api_url: "https://api.braintrust.dev",
      enable_tracing: true
    )
  end

  def teardown
    @state&.span_cache&.stop
  end

  def test_scorer_receives_trace_context
    trace_received = nil

    scorer = Braintrust::Eval::Scorer.new("trace_aware") do |input, expected, output, metadata, trace|
      trace_received = trace
      1.0
    end

    trace_context = Braintrust::TraceContext.new(
      object_type: "experiment",
      object_id: "exp-123",
      root_span_id: "root-abc",
      state: @state
    )

    @state.span_cache.start
    result = scorer.call("input", "expected", "output", {}, trace_context)

    assert_equal 1.0, result
    assert_instance_of Braintrust::TraceContext, trace_received
    assert_equal "exp-123", trace_received.configuration[:object_id]
  end

  def test_scorer_can_query_cached_spans
    spans_queried = nil

    scorer = Braintrust::Eval::Scorer.new("span_query") do |input, expected, output, metadata, trace|
      spans_queried = trace&.get_spans if trace
      1.0
    end

    trace_context = Braintrust::TraceContext.new(
      object_type: "experiment",
      object_id: "exp-123",
      root_span_id: "root-abc",
      state: @state
    )

    @state.span_cache.start
    @state.span_cache.write("root-abc", "span1", {
      input: {messages: [{role: "user", content: "Hello"}]},
      output: {choices: [{message: {role: "assistant", content: "Hi"}}]},
      span_attributes: {type: "llm"}
    })

    result = scorer.call("input", "expected", "output", {}, trace_context)

    assert_equal 1.0, result
    assert_equal 1, spans_queried.size
    assert_equal "llm", spans_queried.first.dig(:span_attributes, :type)
  end

  def test_scorer_can_filter_spans_by_type
    llm_spans_received = nil

    scorer = Braintrust::Eval::Scorer.new("type_filter") do |input, expected, output, metadata, trace|
      llm_spans_received = trace&.get_spans(span_type: "llm") if trace
      1.0
    end

    trace_context = Braintrust::TraceContext.new(
      object_type: "experiment",
      object_id: "exp-123",
      root_span_id: "root-abc",
      state: @state
    )

    @state.span_cache.start
    @state.span_cache.write("root-abc", "span1", {span_attributes: {type: "llm"}})
    @state.span_cache.write("root-abc", "span2", {span_attributes: {type: "task"}})
    @state.span_cache.write("root-abc", "span3", {span_attributes: {type: "llm"}})

    scorer.call("input", "expected", "output", {}, trace_context)

    assert_equal 2, llm_spans_received.size
    llm_spans_received.each do |span|
      assert_equal "llm", span.dig(:span_attributes, :type)
    end
  end

  def test_scorer_can_get_thread
    thread_received = nil

    scorer = Braintrust::Eval::Scorer.new("thread_getter") do |input, expected, output, metadata, trace|
      thread_received = trace&.get_thread if trace
      1.0
    end

    trace_context = Braintrust::TraceContext.new(
      object_type: "experiment",
      object_id: "exp-123",
      root_span_id: "root-abc",
      state: @state
    )

    @state.span_cache.start
    @state.span_cache.write("root-abc", "span1", {
      input: {messages: [{role: "user", content: "Hello"}]},
      output: {choices: [{message: {role: "assistant", content: "Hi"}}]},
      span_attributes: {type: "llm"}
    })

    scorer.call("input", "expected", "output", {}, trace_context)

    assert_equal 2, thread_received.size
    assert_equal "user", thread_received[0][:role]
    assert_equal "assistant", thread_received[1][:role]
  end

  def test_scorer_without_trace_parameter_still_works
    scorer = Braintrust::Eval::Scorer.new("simple") do |input, expected, output|
      (output == expected) ? 1.0 : 0.0
    end

    trace_context = Braintrust::TraceContext.new(
      object_type: "experiment",
      object_id: "exp-123",
      root_span_id: "root-abc",
      state: @state
    )

    result = scorer.call("input", "expected", "expected", {}, trace_context)
    assert_equal 1.0, result
  end

  def test_scorer_filters_out_scorer_spans
    spans_received = nil

    scorer = Braintrust::Eval::Scorer.new("filter_scorer") do |input, expected, output, metadata, trace|
      spans_received = trace&.get_spans if trace
      1.0
    end

    trace_context = Braintrust::TraceContext.new(
      object_type: "experiment",
      object_id: "exp-123",
      root_span_id: "root-abc",
      state: @state
    )

    @state.span_cache.start
    @state.span_cache.write("root-abc", "span1", {span_attributes: {type: "llm"}})
    @state.span_cache.write("root-abc", "span2", {span_attributes: {type: "score", purpose: "scorer"}})
    @state.span_cache.write("root-abc", "span3", {span_attributes: {type: "task"}})

    scorer.call("input", "expected", "output", {}, trace_context)

    assert_equal 2, spans_received.size
    spans_received.each do |span|
      refute_equal "scorer", span.dig(:span_attributes, :purpose)
    end
  end

  def test_span_cache_lifecycle
    refute @state.span_cache.enabled?

    @state.span_cache.start
    assert @state.span_cache.enabled?

    @state.span_cache.write("root1", "span1", {input: "test"})
    spans = @state.span_cache.get("root1")
    assert_equal 1, spans.size

    @state.span_cache.stop
    refute @state.span_cache.enabled?
    assert_equal 0, @state.span_cache.size
  end

  def test_trace_context_configuration
    trace = Braintrust::TraceContext.new(
      object_type: "experiment",
      object_id: "exp-456",
      root_span_id: "root-xyz",
      state: @state
    )

    config = trace.configuration
    assert_equal "experiment", config[:object_type]
    assert_equal "exp-456", config[:object_id]
    assert_equal "root-xyz", config[:root_span_id]
  end

  def test_multiple_scorers_with_trace
    traces_received = []

    scorer1 = Braintrust::Eval::Scorer.new("scorer1") do |input, expected, output, metadata, trace|
      traces_received << trace
      1.0
    end

    scorer2 = Braintrust::Eval::Scorer.new("scorer2") do |input, expected, output, metadata, trace|
      traces_received << trace
      0.5
    end

    trace_context = Braintrust::TraceContext.new(
      object_type: "experiment",
      object_id: "exp-123",
      root_span_id: "root-abc",
      state: @state
    )

    @state.span_cache.start

    scorer1.call("input", "expected", "output", {}, trace_context)
    scorer2.call("input", "expected", "output", {}, trace_context)

    assert_equal 2, traces_received.size
    traces_received.each do |trace|
      assert_instance_of Braintrust::TraceContext, trace
      assert_equal "root-abc", trace.configuration[:root_span_id]
    end
  end
end
