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
  # Return shape — [rows, freshness]
  # ============================================

  def test_trace_spans_returns_rows_and_freshness
    rows_data = [
      {"span_id" => "s1", "name" => "chat"},
      {"span_id" => "s2", "name" => "completion"}
    ]

    stub_request(:post, "#{@state.api_url}/btql")
      .to_return(
        status: 200,
        body: jsonl_body(rows_data),
        headers: fresh_headers
      )

    rows, freshness = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

    assert_equal 2, rows.length
    assert_equal "s1", rows[0]["span_id"]
    assert_equal "s2", rows[1]["span_id"]
    assert_equal "complete", freshness
  end

  def test_trace_spans_returns_stale_freshness
    stub_request(:post, "#{@state.api_url}/btql")
      .to_return(
        status: 200,
        body: jsonl_body([{"span_id" => "s1"}]),
        headers: stale_headers
      )

    rows, freshness = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

    assert_equal 1, rows.length
    assert_equal "incomplete", freshness
  end

  def test_trace_spans_defaults_freshness_to_complete_when_header_missing
    stub_request(:post, "#{@state.api_url}/btql")
      .to_return(
        status: 200,
        body: jsonl_body([{"span_id" => "s1"}]),
        headers: {"Content-Type" => "application/x-jsonlines"}
      )

    rows, freshness = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

    assert_equal 1, rows.length
    assert_equal "complete", freshness
  end

  # ============================================
  # JSONL response parsing
  # ============================================

  def test_trace_spans_handles_empty_lines_in_jsonl
    body = "{\"span_id\":\"s1\"}\n\n{\"span_id\":\"s2\"}\n\n"

    stub_request(:post, "#{@state.api_url}/btql")
      .to_return(
        status: 200,
        body: body,
        headers: fresh_headers
      )

    rows, _freshness = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

    assert_equal 2, rows.length
  end

  # ============================================
  # Errors propagate to caller
  # ============================================

  def test_trace_spans_raises_on_http_error
    stub_request(:post, "#{@state.api_url}/btql")
      .to_return(status: 500, body: "Internal Server Error")

    assert_raises(Braintrust::Error) do
      @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")
    end
  end

  def test_trace_spans_raises_on_network_error
    stub_request(:post, "#{@state.api_url}/btql")
      .to_raise(Errno::ECONNREFUSED)

    assert_raises(Errno::ECONNREFUSED) do
      @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")
    end
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

    rows, _freshness = @btql.trace_spans(object_type: "experiment", object_id: "exp-1", root_span_id: "trace-1")

    assert_equal 1, rows.length
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
