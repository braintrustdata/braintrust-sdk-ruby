# frozen_string_literal: true

require "test_helper"
require "braintrust/eval/trace"

class Braintrust::Eval::TraceTest < Minitest::Test
  # ============================================
  # Lazy loading
  # ============================================

  def test_lazy_loader_not_called_until_spans_accessed
    called = false
    trace = Braintrust::Eval::Trace.new(spans: -> {
      called = true
      []
    })

    refute called, "loader should not be called on initialize"
    trace.spans
    assert called, "loader should be called on first spans access"
  end

  # ============================================
  # Memoization
  # ============================================

  def test_loader_called_once_across_multiple_spans_calls
    call_count = 0
    trace = Braintrust::Eval::Trace.new(spans: -> {
      call_count += 1
      [btql_span(type: "llm")]
    })

    trace.spans
    trace.spans
    trace.spans(span_type: "llm")

    assert_equal 1, call_count
  end

  # ============================================
  # Eager loading
  # ============================================

  def test_eager_spans_returned_directly
    data = [btql_span(type: "llm")]
    trace = Braintrust::Eval::Trace.new(spans: data)

    assert_equal data, trace.spans
  end

  # ============================================
  # Filtering by span_type (via span_attributes.type)
  # ============================================

  def test_spans_filters_by_span_attributes_type
    spans = [
      btql_span(type: "llm", span_id: "s1"),
      btql_span(type: "tool", span_id: "s2"),
      btql_span(type: "llm", span_id: "s3")
    ]
    trace = Braintrust::Eval::Trace.new(spans: spans)

    result = trace.spans(span_type: "llm")

    assert_equal 2, result.length
    assert_equal %w[s1 s3], result.map { |s| s["span_id"] }
  end

  def test_spans_filters_with_symbol_keys
    spans = [
      {span_attributes: {type: "llm"}, span_id: "s1"},
      {span_attributes: {type: "task"}, span_id: "s2"}
    ]
    trace = Braintrust::Eval::Trace.new(spans: spans)

    result = trace.spans(span_type: "llm")

    assert_equal 1, result.length
  end

  def test_nil_span_type_returns_all
    spans = [
      btql_span(type: "llm"),
      btql_span(type: "task"),
      btql_span(type: "eval")
    ]
    trace = Braintrust::Eval::Trace.new(spans: spans)

    assert_equal 3, trace.spans(span_type: nil).length
    assert_equal 3, trace.spans.length
  end

  # ============================================
  # thread method — BTQL flat array format
  # ============================================

  def test_thread_extracts_messages_from_btql_format
    spans = [
      btql_span(
        type: "llm",
        input: [
          {"role" => "system", "content" => "You are helpful."},
          {"role" => "user", "content" => "hello"}
        ],
        output: [
          {"message" => {"role" => "assistant", "content" => "hi"}, "finish_reason" => "stop"}
        ]
      )
    ]
    trace = Braintrust::Eval::Trace.new(spans: spans)

    result = trace.thread

    assert_equal 3, result.length
    assert_equal "system", result[0]["role"]
    assert_equal "user", result[1]["role"]
    assert_equal "assistant", result[2]["role"]
  end

  def test_thread_deduplicates_input_messages_across_spans
    shared_system = {"role" => "system", "content" => "You count fruit."}
    spans = [
      btql_span(
        type: "llm",
        input: [shared_system, {"role" => "user", "content" => "batch 1"}],
        output: [{"message" => {"role" => "assistant", "content" => "2"}}]
      ),
      btql_span(
        type: "llm",
        input: [shared_system, {"role" => "user", "content" => "batch 2"}],
        output: [{"message" => {"role" => "assistant", "content" => "1"}}]
      )
    ]
    trace = Braintrust::Eval::Trace.new(spans: spans)

    result = trace.thread

    # system msg once (deduped), 2 user msgs, 2 assistant msgs = 5
    assert_equal 5, result.length
    system_msgs = result.select { |m| m["role"] == "system" }
    assert_equal 1, system_msgs.length
  end

  def test_thread_handles_missing_input
    spans = [
      btql_span(
        type: "llm",
        input: nil,
        output: [{"message" => {"role" => "assistant", "content" => "hello"}}]
      )
    ]
    trace = Braintrust::Eval::Trace.new(spans: spans)

    result = trace.thread

    assert_equal 1, result.length
    assert_equal "hello", result[0]["content"]
  end

  def test_thread_handles_nil_output
    spans = [
      btql_span(
        type: "llm",
        input: [{"role" => "user", "content" => "hello"}],
        output: nil
      )
    ]
    trace = Braintrust::Eval::Trace.new(spans: spans)

    result = trace.thread

    assert_equal 1, result.length
    assert_equal "hello", result[0]["content"]
  end

  def test_thread_returns_empty_when_no_llm_spans
    spans = [btql_span(type: "task"), btql_span(type: "eval")]
    trace = Braintrust::Eval::Trace.new(spans: spans)

    assert_equal [], trace.thread
  end

  def test_thread_returns_empty_for_empty_spans
    trace = Braintrust::Eval::Trace.new(spans: [])

    assert_equal [], trace.thread
  end

  # ============================================
  # thread method — wrapped format (symbol keys)
  # ============================================

  def test_thread_handles_wrapped_input_output_format
    spans = [
      {
        span_attributes: {type: "llm"},
        input: {messages: [{role: "user", content: "hello"}]},
        output: {choices: [{message: {role: "assistant", content: "hi"}}]}
      }
    ]
    trace = Braintrust::Eval::Trace.new(spans: spans)

    result = trace.thread

    assert_equal 2, result.length
    assert_equal "hello", result[0][:content]
    assert_equal "hi", result[1][:content]
  end

  # ============================================
  # Edge cases
  # ============================================

  def test_nil_spans_source_returns_empty
    trace = Braintrust::Eval::Trace.new(spans: -> {})

    assert_equal [], trace.spans
  end

  private

  # Build a BTQL-shaped span hash (string keys, matching real API response)
  def btql_span(type:, span_id: "s-#{rand(1000)}", input: nil, output: nil)
    span = {
      "span_id" => span_id,
      "span_attributes" => {"type" => type}
    }
    span["input"] = input unless input.nil?
    span["output"] = output unless output.nil?
    span
  end
end
