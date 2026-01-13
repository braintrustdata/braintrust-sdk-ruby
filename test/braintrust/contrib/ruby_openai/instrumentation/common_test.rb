# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/ruby_openai/instrumentation/common"

class Braintrust::Contrib::RubyOpenAI::Instrumentation::CommonTest < Minitest::Test
  Common = Braintrust::Contrib::RubyOpenAI::Instrumentation::Common

  # --- .aggregate_streaming_chunks ---

  def test_aggregate_streaming_chunks_returns_empty_hash_for_empty_input
    assert_equal({}, Common.aggregate_streaming_chunks([]))
  end

  def test_aggregate_streaming_chunks_aggregates_basic_chunks
    chunks = [
      {"id" => "chatcmpl-123", "model" => "gpt-4", "choices" => [{"index" => 0, "delta" => {"role" => "assistant"}}]},
      {"choices" => [{"index" => 0, "delta" => {"content" => "Hello"}}]},
      {"choices" => [{"index" => 0, "delta" => {"content" => " world"}, "finish_reason" => "stop"}]},
      {"usage" => {"prompt_tokens" => 10, "completion_tokens" => 5}}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_equal "chatcmpl-123", result["id"]
    assert_equal "gpt-4", result["model"]
    assert_equal 1, result["choices"].length
    assert_equal "assistant", result["choices"][0]["message"]["role"]
    assert_equal "Hello world", result["choices"][0]["message"]["content"]
    assert_equal "stop", result["choices"][0]["finish_reason"]
    assert_equal({"prompt_tokens" => 10, "completion_tokens" => 5}, result["usage"])
  end

  def test_aggregate_streaming_chunks_captures_system_fingerprint
    chunks = [
      {"id" => "chatcmpl-123", "system_fingerprint" => "fp_abc123", "choices" => [{"index" => 0, "delta" => {"role" => "assistant"}}]},
      {"choices" => [{"index" => 0, "delta" => {"content" => "Hi"}, "finish_reason" => "stop"}]}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_equal "fp_abc123", result["system_fingerprint"]
  end

  def test_aggregate_streaming_chunks_aggregates_tool_calls
    chunks = [
      {"id" => "chatcmpl-123", "choices" => [{"index" => 0, "delta" => {"role" => "assistant", "tool_calls" => [{"id" => "call_abc", "type" => "function", "function" => {"name" => "get_weather", "arguments" => ""}}]}}]},
      {"choices" => [{"index" => 0, "delta" => {"tool_calls" => [{"function" => {"arguments" => '{"loc'}}]}}]},
      {"choices" => [{"index" => 0, "delta" => {"tool_calls" => [{"function" => {"arguments" => 'ation":"NYC"}'}}]}, "finish_reason" => "tool_calls"}]}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_equal 1, result["choices"].length
    assert_equal 1, result["choices"][0]["message"]["tool_calls"].length
    assert_equal "call_abc", result["choices"][0]["message"]["tool_calls"][0]["id"]
    assert_equal "get_weather", result["choices"][0]["message"]["tool_calls"][0]["function"]["name"]
    assert_equal '{"location":"NYC"}', result["choices"][0]["message"]["tool_calls"][0]["function"]["arguments"]
  end

  def test_aggregate_streaming_chunks_handles_multiple_choices
    chunks = [
      {"id" => "chatcmpl-123", "choices" => [
        {"index" => 0, "delta" => {"role" => "assistant"}},
        {"index" => 1, "delta" => {"role" => "assistant"}}
      ]},
      {"choices" => [
        {"index" => 0, "delta" => {"content" => "First"}},
        {"index" => 1, "delta" => {"content" => "Second"}}
      ]},
      {"choices" => [
        {"index" => 0, "delta" => {}, "finish_reason" => "stop"},
        {"index" => 1, "delta" => {}, "finish_reason" => "stop"}
      ]}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_equal 2, result["choices"].length
    assert_equal "First", result["choices"][0]["message"]["content"]
    assert_equal "Second", result["choices"][1]["message"]["content"]
  end

  def test_aggregate_streaming_chunks_returns_nil_content_when_empty
    chunks = [
      {"id" => "chatcmpl-123", "choices" => [{"index" => 0, "delta" => {"role" => "assistant"}}]},
      {"choices" => [{"index" => 0, "delta" => {}, "finish_reason" => "stop"}]}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_nil result["choices"][0]["message"]["content"]
  end

  # --- .aggregate_responses_chunks ---

  def test_aggregate_responses_chunks_returns_empty_hash_for_empty_input
    assert_equal({}, Common.aggregate_responses_chunks([]))
  end

  def test_aggregate_responses_chunks_extracts_completed_event_data
    chunks = [
      {"type" => "response.created"},
      {"type" => "response.in_progress"},
      {
        "type" => "response.completed",
        "response" => {
          "id" => "resp_123",
          "output" => [{"type" => "message", "content" => "Hello"}],
          "usage" => {"input_tokens" => 10, "output_tokens" => 5}
        }
      }
    ]

    result = Common.aggregate_responses_chunks(chunks)

    assert_equal "resp_123", result["id"]
    assert_equal [{"type" => "message", "content" => "Hello"}], result["output"]
    assert_equal({"input_tokens" => 10, "output_tokens" => 5}, result["usage"])
  end

  def test_aggregate_responses_chunks_returns_empty_without_completed_event
    chunks = [
      {"type" => "response.created"},
      {"type" => "response.in_progress"}
    ]

    result = Common.aggregate_responses_chunks(chunks)

    assert_equal({}, result)
  end

  def test_aggregate_responses_chunks_handles_missing_response_fields
    chunks = [
      {
        "type" => "response.completed",
        "response" => {
          "id" => "resp_123"
        }
      }
    ]

    result = Common.aggregate_responses_chunks(chunks)

    assert_equal "resp_123", result["id"]
    assert_nil result["output"]
    assert_nil result["usage"]
  end
end
