# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/openai/instrumentation/common"

class Braintrust::Contrib::OpenAI::Instrumentation::CommonTest < Minitest::Test
  Common = Braintrust::Contrib::OpenAI::Instrumentation::Common

  # --- .aggregate_streaming_chunks ---

  def test_aggregate_streaming_chunks_returns_empty_hash_for_empty_array
    result = Common.aggregate_streaming_chunks([])

    assert_equal({}, result)
  end

  def test_aggregate_streaming_chunks_captures_top_level_fields
    chunks = [
      {id: "chatcmpl-123", created: 1234567890, model: "gpt-4", system_fingerprint: "fp_abc", choices: []}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_equal "chatcmpl-123", result[:id]
    assert_equal 1234567890, result[:created]
    assert_equal "gpt-4", result[:model]
    assert_equal "fp_abc", result[:system_fingerprint]
  end

  def test_aggregate_streaming_chunks_aggregates_content
    chunks = [
      {choices: [{index: 0, delta: {role: "assistant", content: "Hello"}}]},
      {choices: [{index: 0, delta: {content: " world"}}]},
      {choices: [{index: 0, delta: {content: "!"}, finish_reason: "stop"}]}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_equal 1, result[:choices].length
    assert_equal 0, result[:choices][0][:index]
    assert_equal "assistant", result[:choices][0][:message][:role]
    assert_equal "Hello world!", result[:choices][0][:message][:content]
    assert_equal "stop", result[:choices][0][:finish_reason]
  end

  def test_aggregate_streaming_chunks_aggregates_tool_calls
    chunks = [
      {choices: [{index: 0, delta: {role: "assistant", tool_calls: [{id: "call_123", type: "function", function: {name: "get_weather", arguments: '{"loc'}}]}}]},
      {choices: [{index: 0, delta: {tool_calls: [{function: {arguments: 'ation":'}}]}}]},
      {choices: [{index: 0, delta: {tool_calls: [{function: {arguments: '"NYC"}'}}]}, finish_reason: "tool_calls"}]}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_equal 1, result[:choices].length
    tool_calls = result[:choices][0][:message][:tool_calls]
    assert_equal 1, tool_calls.length
    assert_equal "call_123", tool_calls[0][:id]
    assert_equal "function", tool_calls[0][:type]
    assert_equal "get_weather", tool_calls[0][:function][:name]
    assert_equal '{"location":"NYC"}', tool_calls[0][:function][:arguments]
  end

  def test_aggregate_streaming_chunks_captures_usage
    chunks = [
      {choices: [{index: 0, delta: {content: "Hi"}}]},
      {choices: [{index: 0, delta: {}, finish_reason: "stop"}], usage: {prompt_tokens: 10, completion_tokens: 2, total_tokens: 12}}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_equal({prompt_tokens: 10, completion_tokens: 2, total_tokens: 12}, result[:usage])
  end

  def test_aggregate_streaming_chunks_handles_multiple_choices
    chunks = [
      {choices: [{index: 0, delta: {role: "assistant", content: "A"}}, {index: 1, delta: {role: "assistant", content: "B"}}]},
      {choices: [{index: 0, delta: {content: "1"}}, {index: 1, delta: {content: "2"}}]}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_equal 2, result[:choices].length
    assert_equal "A1", result[:choices][0][:message][:content]
    assert_equal "B2", result[:choices][1][:message][:content]
  end

  def test_aggregate_streaming_chunks_sets_nil_content_when_empty
    chunks = [
      {choices: [{index: 0, delta: {role: "assistant", tool_calls: [{id: "call_1", type: "function", function: {name: "foo", arguments: "{}"}}]}, finish_reason: "tool_calls"}]}
    ]

    result = Common.aggregate_streaming_chunks(chunks)

    assert_nil result[:choices][0][:message][:content]
  end

  # --- .aggregate_responses_events ---

  def test_aggregate_responses_events_returns_empty_hash_for_empty_array
    result = Common.aggregate_responses_events([])

    assert_equal({}, result)
  end

  def test_aggregate_responses_events_extracts_from_completed_event
    response = Struct.new(:id, :output, :usage).new("resp_123", [{type: "message", content: "Hello"}], {input_tokens: 5, output_tokens: 3})
    completed_event = Struct.new(:type, :response).new(:"response.completed", response)
    events = [completed_event]

    result = Common.aggregate_responses_events(events)

    assert_equal "resp_123", result[:id]
    assert_equal [{type: "message", content: "Hello"}], result[:output]
    assert_equal({input_tokens: 5, output_tokens: 3}, result[:usage])
  end

  def test_aggregate_responses_events_ignores_non_completed_events
    other_event = Struct.new(:type).new(:"response.created")
    events = [other_event]

    result = Common.aggregate_responses_events(events)

    assert_equal({}, result)
  end

  def test_aggregate_responses_events_handles_missing_response_fields
    response = Struct.new(:id, :output, :usage).new(nil, nil, nil)
    completed_event = Struct.new(:type, :response).new(:"response.completed", response)
    events = [completed_event]

    result = Common.aggregate_responses_events(events)

    assert_nil result[:id]
    assert_nil result[:output]
    assert_nil result[:usage]
  end
end
