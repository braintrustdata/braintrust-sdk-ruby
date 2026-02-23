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
    Thread.current[:braintrust_span_cache_data] = nil
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

    result = scorer.call("input", "expected", "output", {}, trace_context)

    assert_equal 1.0, result
    assert_instance_of Braintrust::TraceContext, trace_received
    assert_equal "exp-123", trace_received.configuration[:object_id]
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
    scorer1.call("input", "expected", "output", {}, trace_context)
    scorer2.call("input", "expected", "output", {}, trace_context)

    assert_equal 2, traces_received.size
    traces_received.each do |trace|
      assert_instance_of Braintrust::TraceContext, trace
      assert_equal "root-abc", trace.configuration[:root_span_id]
    end
  end

  # TODO: Add integration tests with VCR cassettes for:
  # - test_scorer_can_query_spans_via_btql
  # - test_scorer_can_filter_spans_by_type
  # - test_scorer_can_get_thread
  # - test_scorer_filters_out_scorer_spans
  #
  # These tests require proper VCR cassettes with BTQL responses containing spans
end
