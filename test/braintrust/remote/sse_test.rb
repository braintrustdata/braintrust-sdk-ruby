# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::SSETest < Minitest::Test
  # ============================================
  # serialize_event tests
  # ============================================

  def test_serialize_event_with_string_data
    result = Braintrust::Remote::SSE.serialize_event("message", "hello")

    assert_equal "event: message\ndata: hello\n\n", result
  end

  def test_serialize_event_with_hash_data
    result = Braintrust::Remote::SSE.serialize_event("progress", {step: 1, total: 10})

    assert_equal "event: progress\ndata: {\"step\":1,\"total\":10}\n\n", result
  end

  def test_serialize_event_with_nil_data
    result = Braintrust::Remote::SSE.serialize_event("done", nil)

    assert_equal "event: done\ndata: \n\n", result
  end

  def test_serialize_event_with_empty_string
    result = Braintrust::Remote::SSE.serialize_event("empty", "")

    assert_equal "event: empty\ndata: \n\n", result
  end

  def test_serialize_event_with_array_data
    result = Braintrust::Remote::SSE.serialize_event("list", [1, 2, 3])

    assert_equal "event: list\ndata: [1,2,3]\n\n", result
  end

  def test_serialize_event_with_complex_object
    data = {
      id: "row-123",
      scores: {accuracy: 0.95, relevance: 0.87},
      metadata: {timestamp: "2024-01-01"}
    }

    result = Braintrust::Remote::SSE.serialize_event("result", data)

    # Verify it's valid SSE format
    assert result.start_with?("event: result\n")
    assert result.include?("data: ")
    assert result.end_with?("\n\n")

    # Verify the data is valid JSON
    data_line = result.split("\n").find { |l| l.start_with?("data: ") }
    json_str = data_line.sub("data: ", "")
    parsed = JSON.parse(json_str)

    assert_equal "row-123", parsed["id"]
    assert_equal 0.95, parsed["scores"]["accuracy"]
  end

  # ============================================
  # HEADERS constant tests
  # ============================================

  def test_headers_constant_includes_content_type
    assert_equal "text/event-stream; charset=utf-8", Braintrust::Remote::SSE::HEADERS["Content-Type"]
  end

  def test_headers_constant_includes_cache_control
    assert_equal "no-cache", Braintrust::Remote::SSE::HEADERS["Cache-Control"]
  end

  def test_headers_constant_includes_connection
    assert_equal "keep-alive", Braintrust::Remote::SSE::HEADERS["Connection"]
  end

  def test_headers_constant_includes_buffering_header
    assert_equal "no", Braintrust::Remote::SSE::HEADERS["X-Accel-Buffering"]
  end

  # ============================================
  # Edge cases
  # ============================================

  def test_serialize_event_with_special_characters
    result = Braintrust::Remote::SSE.serialize_event(
      "message",
      {text: "Hello\nWorld", quote: "He said \"hi\""}
    )

    # Should be valid SSE
    assert result.start_with?("event: message\n")
    assert result.end_with?("\n\n")

    # Should be parseable JSON
    data_line = result.split("\n").find { |l| l.start_with?("data: ") }
    json_str = data_line.sub("data: ", "")
    parsed = JSON.parse(json_str)

    assert_equal "Hello\nWorld", parsed["text"]
    assert_equal "He said \"hi\"", parsed["quote"]
  end

  def test_serialize_event_with_unicode
    result = Braintrust::Remote::SSE.serialize_event(
      "message",
      {greeting: "こんにちは", emoji: "👋"}
    )

    data_line = result.split("\n").find { |l| l.start_with?("data: ") }
    json_str = data_line.sub("data: ", "")
    parsed = JSON.parse(json_str)

    assert_equal "こんにちは", parsed["greeting"]
    assert_equal "👋", parsed["emoji"]
  end

  def test_serialize_event_with_numeric_data
    result = Braintrust::Remote::SSE.serialize_event("score", 0.95)

    assert_equal "event: score\ndata: 0.95\n\n", result
  end

  def test_serialize_event_with_boolean_data
    result_true = Braintrust::Remote::SSE.serialize_event("flag", true)
    result_false = Braintrust::Remote::SSE.serialize_event("flag", false)

    assert_equal "event: flag\ndata: true\n\n", result_true
    assert_equal "event: flag\ndata: false\n\n", result_false
  end
end
