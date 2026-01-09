# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/openai/instrumentation/common"

class Braintrust::Contrib::OpenAI::Instrumentation::CommonTest < Minitest::Test
  # ============================
  # aggregate_streaming_chunks
  # ============================

  def test_aggregate_streaming_chunks_empty
    assert_equal({}, Braintrust::Contrib::OpenAI::Instrumentation::Common.aggregate_streaming_chunks([]))
  end

  def test_aggregate_streaming_chunks_basic
    chunks = [
      {id: "chatcmpl-123", model: "gpt-4", choices: [{index: 0, delta: {role: "assistant"}}]},
      {choices: [{index: 0, delta: {content: "Hello"}}]},
      {choices: [{index: 0, delta: {content: " world"}, finish_reason: "stop"}]},
      {usage: {prompt_tokens: 10, completion_tokens: 5}}
    ]

    result = Braintrust::Contrib::OpenAI::Instrumentation::Common.aggregate_streaming_chunks(chunks)

    assert_equal "chatcmpl-123", result[:id]
    assert_equal "gpt-4", result[:model]
    assert_equal 1, result[:choices].length
    assert_equal "assistant", result[:choices][0][:message][:role]
    assert_equal "Hello world", result[:choices][0][:message][:content]
    assert_equal "stop", result[:choices][0][:finish_reason]
    assert_equal 10, result[:usage][:prompt_tokens]
  end

  def test_aggregate_streaming_chunks_captures_system_fingerprint
    chunks = [
      {id: "chatcmpl-123", system_fingerprint: "fp_abc123", choices: [{index: 0, delta: {role: "assistant"}}]},
      {choices: [{index: 0, delta: {content: "Hi"}, finish_reason: "stop"}]}
    ]

    result = Braintrust::Contrib::OpenAI::Instrumentation::Common.aggregate_streaming_chunks(chunks)

    assert_equal "fp_abc123", result[:system_fingerprint]
  end

  def test_aggregate_streaming_chunks_with_tool_calls
    chunks = [
      {id: "chatcmpl-123", choices: [{index: 0, delta: {role: "assistant", tool_calls: [{id: "call_abc", type: "function", function: {name: "get_weather", arguments: ""}}]}}]},
      {choices: [{index: 0, delta: {tool_calls: [{function: {arguments: '{"loc'}}]}}]},
      {choices: [{index: 0, delta: {tool_calls: [{function: {arguments: 'ation":"NYC"}'}}]}, finish_reason: "tool_calls"}]}
    ]

    result = Braintrust::Contrib::OpenAI::Instrumentation::Common.aggregate_streaming_chunks(chunks)

    assert_equal 1, result[:choices].length
    assert_equal 1, result[:choices][0][:message][:tool_calls].length
    assert_equal "call_abc", result[:choices][0][:message][:tool_calls][0][:id]
    assert_equal "get_weather", result[:choices][0][:message][:tool_calls][0][:function][:name]
    assert_equal '{"location":"NYC"}', result[:choices][0][:message][:tool_calls][0][:function][:arguments]
  end

  def test_aggregate_streaming_chunks_multiple_choices
    chunks = [
      {id: "chatcmpl-123", choices: [
        {index: 0, delta: {role: "assistant"}},
        {index: 1, delta: {role: "assistant"}}
      ]},
      {choices: [
        {index: 0, delta: {content: "First"}},
        {index: 1, delta: {content: "Second"}}
      ]},
      {choices: [
        {index: 0, delta: {}, finish_reason: "stop"},
        {index: 1, delta: {}, finish_reason: "stop"}
      ]}
    ]

    result = Braintrust::Contrib::OpenAI::Instrumentation::Common.aggregate_streaming_chunks(chunks)

    assert_equal 2, result[:choices].length
    assert_equal "First", result[:choices][0][:message][:content]
    assert_equal "Second", result[:choices][1][:message][:content]
  end

  def test_aggregate_streaming_chunks_empty_content_is_nil
    chunks = [
      {id: "chatcmpl-123", choices: [{index: 0, delta: {role: "assistant"}}]},
      {choices: [{index: 0, delta: {}, finish_reason: "stop"}]}
    ]

    result = Braintrust::Contrib::OpenAI::Instrumentation::Common.aggregate_streaming_chunks(chunks)

    assert_nil result[:choices][0][:message][:content]
  end

  # ============================
  # aggregate_responses_events
  # ============================

  def test_aggregate_responses_events_empty
    assert_equal({}, Braintrust::Contrib::OpenAI::Instrumentation::Common.aggregate_responses_events([]))
  end

  def test_aggregate_responses_events_with_completed_event
    # Create mock event objects that respond to :type and :response
    completed_response = Struct.new(:id, :output, :usage, keyword_init: true).new(
      id: "resp_123",
      output: [{"type" => "message", "content" => "Hello"}],
      usage: {input_tokens: 10, output_tokens: 5}
    )

    completed_event = Struct.new(:type, :response, keyword_init: true).new(
      type: :"response.completed",
      response: completed_response
    )

    events = [
      Struct.new(:type).new(:"response.created"),
      Struct.new(:type).new(:"response.in_progress"),
      completed_event
    ]

    result = Braintrust::Contrib::OpenAI::Instrumentation::Common.aggregate_responses_events(events)

    assert_equal "resp_123", result[:id]
    assert_equal [{"type" => "message", "content" => "Hello"}], result[:output]
    assert_equal({input_tokens: 10, output_tokens: 5}, result[:usage])
  end

  def test_aggregate_responses_events_without_completed_event
    events = [
      Struct.new(:type).new(:"response.created"),
      Struct.new(:type).new(:"response.in_progress")
    ]

    result = Braintrust::Contrib::OpenAI::Instrumentation::Common.aggregate_responses_events(events)

    assert_equal({}, result)
  end

  def test_aggregate_responses_events_handles_missing_response_fields
    completed_response = Struct.new(:id, keyword_init: true).new(id: "resp_123")

    completed_event = Struct.new(:type, :response, keyword_init: true).new(
      type: :"response.completed",
      response: completed_response
    )

    events = [completed_event]

    result = Braintrust::Contrib::OpenAI::Instrumentation::Common.aggregate_responses_events(events)

    assert_equal "resp_123", result[:id]
    assert_nil result[:output]
    assert_nil result[:usage]
  end
end
