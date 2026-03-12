# frozen_string_literal: true

require "test_helper"
require "braintrust/api/internal/btql"

class Braintrust::API::Internal::BTQLTest < Minitest::Test
  def setup
    @state = get_unit_test_state
    @btql = Braintrust::API::Internal::BTQL.new(@state)
  end

  # ============================================
  # trace_spans — query building
  # ============================================

  def test_trace_spans_builds_correct_sql_query
    captured_body = nil

    stub_request(:post, "#{@state.api_url}/btql")
      .with { |req|
        captured_body = JSON.parse(req.body)
        true
      }
      .to_return(
        status: 200,
        body: jsonl_body([{"span_id" => "s1"}]),
        headers: fresh_headers
      )

    @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "abc123")

    query = captured_body["query"]
    assert_includes query, "SELECT * FROM experiment('exp-1')"
    assert_includes query, "root_span_id = 'abc123'"
    assert_includes query, "span_attributes.type != 'score'"
    assert_includes query, "LIMIT 1000"
    assert_equal "jsonl", captured_body["fmt"]
  end

  def test_trace_spans_escapes_single_quotes
    captured_body = nil

    stub_request(:post, "#{@state.api_url}/btql")
      .with { |req|
        captured_body = JSON.parse(req.body)
        true
      }
      .to_return(
        status: 200,
        body: jsonl_body([{"span_id" => "s1"}]),
        headers: fresh_headers
      )

    @btql.trace_spans(object_type: "experiment", object_id: "exp-'inject", root_span_id: "abc'123")

    query = captured_body["query"]
    assert_includes query, "experiment('exp-''inject')"
    assert_includes query, "root_span_id = 'abc''123'"
  end

  # ============================================
  # JSONL response parsing
  # ============================================

  def test_trace_spans_parses_jsonl_response
    rows = [
      {"span_id" => "s1", "name" => "chat"},
      {"span_id" => "s2", "name" => "completion"}
    ]

    stub_request(:post, "#{@state.api_url}/btql")
      .to_return(
        status: 200,
        body: jsonl_body(rows),
        headers: fresh_headers
      )

    result = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

    assert_equal 2, result.length
    assert_equal "s1", result[0]["span_id"]
    assert_equal "s2", result[1]["span_id"]
  end

  def test_trace_spans_handles_empty_lines_in_jsonl
    body = "{\"span_id\":\"s1\"}\n\n{\"span_id\":\"s2\"}\n\n"

    stub_request(:post, "#{@state.api_url}/btql")
      .to_return(
        status: 200,
        body: body,
        headers: fresh_headers
      )

    result = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

    assert_equal 2, result.length
  end

  # ============================================
  # Freshness retry
  # ============================================

  def test_trace_spans_retries_when_freshness_incomplete
    call_count = 0

    stub_request(:post, "#{@state.api_url}/btql")
      .to_return do |_request|
        call_count += 1
        if call_count < 3
          {status: 200, body: "", headers: stale_headers}
        else
          {status: 200, body: jsonl_body([{"span_id" => "s1"}]), headers: fresh_headers}
        end
      end

    Braintrust::API::Internal::BTQL.stub_const(:FRESHNESS_BASE_DELAY, 0.001) do
      result = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

      assert_equal 1, result.length
      assert_equal "s1", result[0]["span_id"]
      assert_equal 3, call_count
    end
  end

  def test_trace_spans_retries_when_fresh_but_empty
    call_count = 0

    stub_request(:post, "#{@state.api_url}/btql")
      .to_return do |_request|
        call_count += 1
        {status: 200, body: "", headers: fresh_headers}
      end

    Braintrust::API::Internal::BTQL.stub_const(:FRESHNESS_BASE_DELAY, 0.001) do
      result = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

      assert_equal [], result
      # 1 initial + MAX_FRESHNESS_RETRIES retries = 8 total calls
      assert_equal 8, call_count, "should retry when fresh but empty (ingestion lag)"
    end
  end

  def test_trace_spans_returns_immediately_when_fresh_with_data
    call_count = 0

    stub_request(:post, "#{@state.api_url}/btql")
      .to_return do |_request|
        call_count += 1
        {status: 200, body: jsonl_body([{"span_id" => "s1"}]), headers: fresh_headers}
      end

    result = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

    assert_equal 1, result.length
    assert_equal 1, call_count, "should not retry when fresh and has data"
  end

  def test_trace_spans_returns_partial_after_max_retries
    stub_request(:post, "#{@state.api_url}/btql")
      .to_return(
        status: 200,
        body: jsonl_body([{"span_id" => "s1"}]),
        headers: stale_headers
      )

    Braintrust::API::Internal::BTQL.stub_const(:FRESHNESS_BASE_DELAY, 0.001) do
      result = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

      # Returns whatever we have after exhausting retries, even if stale
      assert_equal 1, result.length
      assert_equal "s1", result[0]["span_id"]
    end
  end

  def test_trace_spans_defaults_to_complete_when_header_missing
    call_count = 0

    stub_request(:post, "#{@state.api_url}/btql")
      .to_return do |_request|
        call_count += 1
        {status: 200, body: jsonl_body([{"span_id" => "s1"}]),
         headers: {"Content-Type" => "application/x-jsonlines"}}
      end

    result = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

    assert_equal 1, result.length
    assert_equal 1, call_count, "missing header should default to complete (no retry)"
  end

  # ============================================
  # Error handling
  # ============================================

  def test_trace_spans_returns_empty_on_http_error
    stub_request(:post, "#{@state.api_url}/btql")
      .to_return(status: 500, body: "Internal Server Error")

    result = suppress_logs { @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1") }

    assert_equal [], result
  end

  def test_trace_spans_returns_empty_on_network_error
    stub_request(:post, "#{@state.api_url}/btql")
      .to_raise(Errno::ECONNREFUSED)

    result = suppress_logs { @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1") }

    assert_equal [], result
  end

  # ============================================
  # Authorization header
  # ============================================

  def test_trace_spans_sends_authorization_header
    stub_request(:post, "#{@state.api_url}/btql")
      .with(headers: {"Authorization" => "Bearer #{@state.api_key}"})
      .to_return(
        status: 200,
        body: jsonl_body([{"span_id" => "s1"}]),
        headers: fresh_headers
      )

    result = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

    assert_equal 1, result.length
  end

  private

  def jsonl_body(rows)
    rows.map { |r| JSON.dump(r) }.join("\n") + "\n"
  end

  def fresh_headers
    {"Content-Type" => "application/x-jsonlines", "x-bt-freshness-state" => "complete"}
  end

  def stale_headers
    {"Content-Type" => "application/x-jsonlines", "x-bt-freshness-state" => "incomplete"}
  end
end
