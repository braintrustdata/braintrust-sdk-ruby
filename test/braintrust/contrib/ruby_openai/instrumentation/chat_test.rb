# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/ruby_openai/instrumentation/chat"

class Braintrust::Contrib::RubyOpenAI::Instrumentation::ChatTest < Minitest::Test
  Chat = Braintrust::Contrib::RubyOpenAI::Instrumentation::Chat

  # --- .included ---

  def test_included_prepends_instance_methods
    base = Class.new
    mock = Minitest::Mock.new
    mock.expect(:include?, false, [Chat::InstanceMethods])
    mock.expect(:prepend, nil, [Chat::InstanceMethods])

    base.define_singleton_method(:ancestors) { mock }
    base.define_singleton_method(:prepend) { |mod| mock.prepend(mod) }

    Chat.included(base)

    mock.verify
  end

  def test_included_skips_prepend_when_already_applied
    base = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Chat
    end

    # Should not raise or double-prepend
    Chat.included(base)

    # InstanceMethods should appear only once in ancestors
    count = base.ancestors.count { |a| a == Chat::InstanceMethods }
    assert_equal 1, count
  end

  # --- .applied? ---

  def test_applied_returns_false_when_not_included
    base = Class.new

    refute Chat.applied?(base)
  end

  def test_applied_returns_true_when_included
    base = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Chat
    end

    assert Chat.applied?(base)
  end
end

# E2E tests for Chat instrumentation
class Braintrust::Contrib::RubyOpenAI::Instrumentation::ChatE2ETest < Minitest::Test
  def setup
    skip "OpenAI module not defined" unless defined?(::OpenAI)

    # Skip if official openai gem is loaded (has OpenAI::Internal)
    if defined?(::OpenAI::Internal)
      skip "ruby-openai gem not available (found official openai gem instead)"
    elsif !Gem.loaded_specs["ruby-openai"]
      skip "ruby-openai gem not available"
    end

    @api_key = ENV["OPENAI_API_KEY"] || "test-api-key"
  end

  # --- #chat ---

  def test_chat_creates_span_with_correct_attributes
    VCR.use_cassette("alexrudall_ruby_openai/chat_completions") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {role: "system", content: "You are a test assistant."},
            {role: "user", content: "Say 'test'"}
          ],
          max_tokens: 10,
          temperature: 0.5
        }
      )

      refute_nil response
      refute_nil response.dig("choices", 0, "message", "content")

      span = rig.drain_one

      assert_equal "Chat Completion", span.name

      # Verify braintrust.input_json contains messages with content
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 2, input.length
      assert_equal "system", input[0]["role"]
      assert_equal "You are a test assistant.", input[0]["content"]
      assert_equal "user", input[1]["role"]
      assert_equal "Say 'test'", input[1]["content"]

      # Verify braintrust.output_json contains choices with full details
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal 0, output[0]["index"]
      assert_equal "assistant", output[0]["message"]["role"]
      refute_nil output[0]["message"]["content"]
      refute_nil output[0]["finish_reason"]

      # Verify braintrust.metadata contains request and response metadata
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal "/v1/chat/completions", metadata["endpoint"]
      assert_match(/\Agpt-4o-mini/, metadata["model"])
      assert_equal 10, metadata["max_tokens"]
      assert_equal 0.5, metadata["temperature"]
      refute_nil metadata["id"]
      refute_nil metadata["created"]

      # Verify braintrust.metrics contains token usage
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics["tokens"] > 0
      assert_equal metrics["prompt_tokens"] + metrics["completion_tokens"], metrics["tokens"]
      assert metrics.key?("time_to_first_token")
      assert metrics["time_to_first_token"] >= 0
    end
  end

  def test_chat_handles_tool_calls
    VCR.use_cassette("alexrudall_ruby_openai/tool_calls") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      tools = [
        {
          type: "function",
          function: {
            name: "get_weather",
            description: "Get the current weather",
            parameters: {
              type: "object",
              properties: {
                location: {type: "string", description: "City name"}
              },
              required: ["location"]
            }
          }
        }
      ]

      response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {role: "user", content: "What's the weather in Paris?"}
          ],
          tools: tools,
          max_tokens: 100
        }
      )

      refute_nil response

      span = rig.drain_one

      assert_equal "Chat Completion", span.name

      # Verify input was captured
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]

      # Verify output contains tool calls
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length

      # Verify metadata includes tools
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      refute_nil metadata["tools"]
    end
  end

  def test_chat_handles_multi_turn_tool_calls
    VCR.use_cassette("alexrudall_ruby_openai/multi_turn_tools") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      tools = [
        {
          type: "function",
          function: {
            name: "calculate",
            description: "Perform a calculation",
            parameters: {
              type: "object",
              properties: {
                operation: {type: "string"},
                a: {type: "number"},
                b: {type: "number"}
              }
            }
          }
        }
      ]

      # First request - model calls tool
      first_response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {role: "user", content: "What is 127 multiplied by 49?"}
          ],
          tools: tools,
          max_tokens: 100
        }
      )

      tool_call = first_response.dig("choices", 0, "message", "tool_calls", 0)
      skip "Model didn't call tool" unless tool_call

      # Second request - provide tool result with tool_call_id
      second_response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {role: "user", content: "What is 127 multiplied by 49?"},
            first_response.dig("choices", 0, "message"),  # Assistant message with tool_calls
            {
              role: "tool",
              tool_call_id: tool_call["id"],
              content: "6223"
            }
          ],
          tools: tools,
          max_tokens: 100
        }
      )

      # Verify response
      refute_nil second_response

      # Drain spans (we have 2: first request + second request)
      spans = rig.drain
      assert_equal 2, spans.length

      # Verify second span contains tool_call_id in input
      span = spans[1]
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 3, input.length

      # Third message should be tool response with tool_call_id
      assert_equal "tool", input[2]["role"]
      assert_equal tool_call["id"], input[2]["tool_call_id"]
      assert_equal "6223", input[2]["content"]
    end
  end

  def test_chat_handles_streaming
    VCR.use_cassette("alexrudall_ruby_openai/streaming") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      full_content = ""
      client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {role: "user", content: "Count from 1 to 3"}
          ],
          max_tokens: 50,
          stream_options: {include_usage: true},
          stream: proc do |chunk, _bytesize|
            delta_content = chunk.dig("choices", 0, "delta", "content")
            full_content += delta_content if delta_content
          end
        }
      )

      refute_empty full_content

      span = rig.drain_one

      assert_equal "Chat Completion", span.name

      # Verify input was captured
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]

      # Verify output was captured and aggregated
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal 0, output[0]["index"]
      assert_equal "assistant", output[0]["message"]["role"]
      refute_nil output[0]["message"]["content"]
      refute_empty output[0]["message"]["content"]

      # Verify metadata includes stream flag
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal true, metadata["stream"]

      # Verify metrics include time_to_first_token and usage tokens
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics.key?("time_to_first_token")
      assert metrics["time_to_first_token"] >= 0
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics["tokens"] > 0
      assert_equal metrics["prompt_tokens"] + metrics["completion_tokens"], metrics["tokens"]
    end
  end

  def test_chat_records_exception_on_error
    VCR.use_cassette("alexrudall_ruby_openai/error") do
      rig = setup_otel_test_rig

      client = OpenAI::Client.new(access_token: "invalid_key")
      Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: rig.tracer_provider)

      error = assert_raises do
        client.chat(
          parameters: {
            model: "gpt-4o-mini",
            messages: [{role: "user", content: "test"}]
          }
        )
      end

      refute_nil error

      span = rig.drain_one

      assert_equal "Chat Completion", span.name
      assert_equal OpenTelemetry::Trace::Status::ERROR, span.status.code

      # Verify error message is captured
      refute_nil span.status.description
      assert span.status.description.length > 0

      # Verify exception event was recorded
      assert span.events.any? { |event| event.name == "exception" }
    end
  end
end
