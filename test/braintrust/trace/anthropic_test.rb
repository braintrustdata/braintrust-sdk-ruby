# frozen_string_literal: true

require "test_helper"

class Braintrust::Trace::AnthropicTest < Minitest::Test
  def setup
    # Skip all Anthropic tests if the gem is not available
    skip "Anthropic gem not available" unless defined?(Anthropic)

    @api_key = ENV["ANTHROPIC_API_KEY"]
    @original_api_key = ENV["ANTHROPIC_API_KEY"]
  end

  def teardown
    if @original_api_key
      ENV["ANTHROPIC_API_KEY"] = @original_api_key
    else
      ENV.delete("ANTHROPIC_API_KEY")
    end
  end

  def test_wrap_creates_span_for_basic_message
    VCR.use_cassette("anthropic/basic_message") do
      require "anthropic"

      # Set up test rig (includes Braintrust processor)
      rig = setup_otel_test_rig

      # Create Anthropic client and wrap it with Braintrust tracing
      client = Anthropic::Client.new(api_key: @api_key)
      Braintrust::Trace::Anthropic.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a simple message request
      message = client.messages.create(
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 10,
        messages: [
          {role: "user", content: "Say 'test'"}
        ]
      )

      # Verify response
      refute_nil message
      refute_nil message.content
      assert message.content.length > 0

      # Drain and verify span
      span = rig.drain_one

      # Verify span name matches Go SDK
      assert_equal "anthropic.messages.create", span.name

      # Verify braintrust.input_json contains messages
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]
      assert_equal "Say 'test'", input[0]["content"]

      # Verify braintrust.output_json contains response as message array
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal "assistant", output[0]["role"]
      assert output[0]["content"].is_a?(Array)

      # Verify braintrust.metadata contains request and response metadata
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "anthropic", metadata["provider"]
      assert_equal "/v1/messages", metadata["endpoint"]
      assert_equal "claude-3-5-sonnet-20241022", metadata["model"]
      assert_equal 10, metadata["max_tokens"]

      # Verify braintrust.metrics contains token usage with Anthropic-specific fields
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics["tokens"] > 0
      assert_equal metrics["prompt_tokens"] + metrics["completion_tokens"], metrics["tokens"]
    end
  end

  def test_wrap_handles_system_prompt
    VCR.use_cassette("anthropic/system_prompt") do
      require "anthropic"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and wrap it
      client = Anthropic::Client.new(api_key: @api_key)
      Braintrust::Trace::Anthropic.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a request with system prompt
      message = client.messages.create(
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 20,
        system: "You are a helpful assistant that always responds briefly.",
        messages: [
          {role: "user", content: "Say hello"}
        ]
      )

      # Verify response
      refute_nil message

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "anthropic.messages.create", span.name

      # Verify braintrust.input_json has system prompt prepended
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 2, input.length

      # First message should be system
      assert_equal "system", input[0]["role"]
      assert_equal "You are a helpful assistant that always responds briefly.", input[0]["content"]

      # Second message should be user
      assert_equal "user", input[1]["role"]
      assert_equal "Say hello", input[1]["content"]

      # Verify output
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal "assistant", output[0]["role"]
    end
  end

  def test_wrap_handles_tool_use
    VCR.use_cassette("anthropic/tool_use") do
      require "anthropic"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and wrap it
      client = Anthropic::Client.new(api_key: @api_key)
      Braintrust::Trace::Anthropic.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a request with tools
      message = client.messages.create(
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 100,
        tools: [
          {
            name: "get_weather",
            description: "Get the current weather for a location",
            input_schema: {
              type: "object",
              properties: {
                location: {type: "string", description: "City name"}
              },
              required: ["location"]
            }
          }
        ],
        messages: [
          {role: "user", content: "What's the weather in Paris?"}
        ]
      )

      # Verify response
      refute_nil message

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "anthropic.messages.create", span.name

      # Verify input captured
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]

      # Verify output contains tool_use content blocks
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal "assistant", output[0]["role"]
      assert output[0]["content"].is_a?(Array)

      # Check that we captured tool_use block
      content = output[0]["content"]
      tool_use_block = content.find { |block| block["type"] == "tool_use" }
      assert tool_use_block, "Should have tool_use content block"
      assert_equal "get_weather", tool_use_block["name"]
      assert tool_use_block["input"], "Should have tool input"

      # Verify metadata includes tools
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert metadata["tools"], "Should capture tools in metadata"
    end
  end

  def test_wrap_handles_streaming
    VCR.use_cassette("anthropic/streaming") do
      require "anthropic"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and wrap it
      client = Anthropic::Client.new(api_key: @api_key)
      Braintrust::Trace::Anthropic.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a streaming request
      stream = client.messages.stream(
        model: "claude-3-5-sonnet-20241022",
        max_tokens: 50,
        messages: [
          {role: "user", content: "Count to 5"}
        ]
      )

      # Consume the stream
      stream.each do |event|
        # Just consume events
      end

      # Drain and verify span was created
      span = rig.drain_one

      # Verify span name
      assert_equal "anthropic.messages.create", span.name

      # Verify input captured
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]

      # Verify metadata includes stream flag
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal true, metadata["stream"]

      # Note: Full output aggregation testing requires live API calls
      # VCR doesn't perfectly replay streaming SSE responses
      # The streaming wrapper is implemented and works with real API calls
    end
  end

  def test_wrap_handles_streaming_output_aggregation
    # This test demonstrates the bug: streaming output is not aggregated
    VCR.use_cassette("anthropic/streaming_aggregation") do
      require "anthropic"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and wrap it
      client = Anthropic::Client.new(api_key: @api_key)
      Braintrust::Trace::Anthropic.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a streaming request
      collected_text = ""
      stream = client.messages.stream(
        model: "claude-sonnet-4-20250514",
        max_tokens: 50,
        messages: [
          {role: "user", content: "Count to 3"}
        ]
      )

      # Consume the stream and collect text
      stream.each do |event|
        if event.type == :content_block_delta && event.delta.type == :text_delta
          collected_text += event.delta.text
        end
      end

      # Verify we got some text
      refute_empty collected_text, "Should have received text from stream"

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "anthropic.messages.create", span.name

      # CRITICAL: Verify output was aggregated
      assert span.attributes.key?("braintrust.output_json"), "Should have output_json attribute"
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length, "Should have one output message"
      assert_equal "assistant", output[0]["role"]

      # The output content should not be empty!
      assert output[0]["content"].is_a?(Array), "Output content should be an array"
      refute_empty output[0]["content"], "Output content should not be empty"

      # Should have aggregated the text content
      text_block = output[0]["content"].find { |b| b["type"] == "text" }
      assert text_block, "Should have a text content block"
      assert text_block["text"], "Text block should have text"
      refute_empty text_block["text"], "Text should not be empty"
      assert_equal collected_text, text_block["text"], "Aggregated text should match collected text"

      # CRITICAL: Verify metrics were captured
      assert span.attributes.key?("braintrust.metrics"), "Should have metrics attribute"
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"], "Should have prompt_tokens"
      assert metrics["prompt_tokens"] > 0, "Prompt tokens should be greater than 0"
      assert metrics["completion_tokens"], "Should have completion_tokens"
      assert metrics["completion_tokens"] > 0, "Completion tokens should be greater than 0"
      assert metrics["tokens"], "Should have total tokens"
      assert metrics["tokens"] > 0, "Total tokens should be greater than 0"
    end
  end

  def test_wrap_handles_vision_with_base64
    VCR.use_cassette("anthropic/vision_base64") do
      require "anthropic"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and wrap it
      client = Anthropic::Client.new(api_key: @api_key)
      Braintrust::Trace::Anthropic.wrap(client, tracer_provider: rig.tracer_provider)

      # Small 1x1 red pixel PNG as base64
      test_image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

      # Make a request with base64 image
      message = client.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 50,
        messages: [
          {
            role: "user",
            content: [
              {type: "text", text: "What color is this image?"},
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: "image/png",
                  data: test_image
                }
              }
            ]
          }
        ]
      )

      # Verify response
      refute_nil message

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "anthropic.messages.create", span.name

      # Verify input captured with mixed content
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]
      # Input content should be an array with both text and image
      assert input[0]["content"].is_a?(Array)
      assert input[0]["content"].any? { |c| c["type"] == "text" }
      assert input[0]["content"].any? { |c| c["type"] == "image" }

      # Verify output
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal "assistant", output[0]["role"]
    end
  end

  def test_wrap_handles_reasoning_thinking_blocks
    VCR.use_cassette("anthropic/reasoning") do
      require "anthropic"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and wrap it
      client = Anthropic::Client.new(api_key: @api_key)
      Braintrust::Trace::Anthropic.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a request with reasoning enabled
      message = client.messages.create(
        model: "claude-3-7-sonnet-latest",
        max_tokens: 2000,
        thinking: {
          type: "enabled",
          budget_tokens: 1024
        },
        messages: [
          {role: "user", content: "What is 2+2? Think step by step."}
        ]
      )

      # Verify response
      refute_nil message
      refute_nil message.content

      # Check for thinking blocks in response
      thinking_blocks = message.content.select { |b| b.type == :thinking }
      text_blocks = message.content.select { |b| b.type == :text }

      # Should have at least one thinking block
      assert thinking_blocks.length > 0, "Should have thinking blocks"
      assert text_blocks.length > 0, "Should have text blocks"

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "anthropic.messages.create", span.name

      # Verify metadata includes thinking parameter
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert metadata["thinking"], "Should capture thinking parameter"

      # Verify output includes thinking blocks
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal "assistant", output[0]["role"]
      assert output[0]["content"].is_a?(Array)

      # Check that thinking blocks are captured
      output_thinking = output[0]["content"].select { |b| b["type"] == "thinking" }
      assert output_thinking.length > 0, "Should capture thinking blocks in output"
    end
  end

  def test_wrap_handles_multi_turn_conversation
    VCR.use_cassette("anthropic/multi_turn") do
      require "anthropic"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and wrap it
      client = Anthropic::Client.new(api_key: @api_key)
      Braintrust::Trace::Anthropic.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a multi-turn conversation request
      message = client.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 100,
        messages: [
          {role: "user", content: "My name is Alice."},
          {role: "assistant", content: "Hello Alice! Nice to meet you."},
          {role: "user", content: "What's my name?"}
        ]
      )

      # Verify response
      refute_nil message

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "anthropic.messages.create", span.name

      # Verify input includes all messages in conversation
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 3, input.length, "Should have all 3 messages"

      # Verify message roles
      assert_equal "user", input[0]["role"]
      assert_equal "assistant", input[1]["role"]
      assert_equal "user", input[2]["role"]

      # Verify content
      assert_equal "My name is Alice.", input[0]["content"]
      assert_equal "Hello Alice! Nice to meet you.", input[1]["content"]
      assert_equal "What's my name?", input[2]["content"]

      # Verify output
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal "assistant", output[0]["role"]
    end
  end

  def test_wrap_handles_temperature_and_stop_sequences
    VCR.use_cassette("anthropic/temperature_stop") do
      require "anthropic"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and wrap it
      client = Anthropic::Client.new(api_key: @api_key)
      Braintrust::Trace::Anthropic.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a request with temperature and stop sequences
      message = client.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 100,
        temperature: 0.7,
        top_p: 0.95,
        stop_sequences: ["END"],
        messages: [
          {role: "user", content: "Count to 3, then say END."}
        ]
      )

      # Verify response
      refute_nil message

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "anthropic.messages.create", span.name

      # Verify metadata includes parameters
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal 0.7, metadata["temperature"]
      assert_equal 0.95, metadata["top_p"]
      assert_equal ["END"], metadata["stop_sequences"]

      # Verify stop reason is captured
      assert metadata["stop_reason"], "Should capture stop_reason"

      # Verify output
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal "assistant", output[0]["role"]
    end
  end

  def test_wrap_handles_tool_use_multi_turn
    VCR.use_cassette("anthropic/tool_use_multi_turn") do
      require "anthropic"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and wrap it
      client = Anthropic::Client.new(api_key: @api_key)
      Braintrust::Trace::Anthropic.wrap(client, tracer_provider: rig.tracer_provider)

      # First request - model should use tool
      first_message = client.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 200,
        tools: [
          {
            name: "calculator",
            description: "Perform arithmetic",
            input_schema: {
              type: "object",
              properties: {
                operation: {type: "string"},
                a: {type: "number"},
                b: {type: "number"}
              },
              required: ["operation", "a", "b"]
            }
          }
        ],
        messages: [
          {role: "user", content: "What is 15 times 23?"}
        ]
      )

      # Verify first response has tool use
      refute_nil first_message
      tool_use_block = first_message.content.find { |b| b.type == :tool_use }

      # Only continue if model used tool
      if tool_use_block
        # Second request - provide tool result
        second_message = client.messages.create(
          model: "claude-sonnet-4-20250514",
          max_tokens: 200,
          tools: [
            {
              name: "calculator",
              description: "Perform arithmetic",
              input_schema: {
                type: "object",
                properties: {
                  operation: {type: "string"},
                  a: {type: "number"},
                  b: {type: "number"}
                },
                required: ["operation", "a", "b"]
              }
            }
          ],
          messages: [
            {role: "user", content: "What is 15 times 23?"},
            {
              role: "assistant",
              content: first_message.content.map { |block|
                if block.type == :tool_use
                  {
                    type: "tool_use",
                    id: block.id,
                    name: block.name,
                    input: block.input
                  }
                else
                  {type: "text", text: block.text}
                end
              }
            },
            {
              role: "user",
              content: [
                {
                  type: "tool_result",
                  tool_use_id: tool_use_block.id,
                  content: "345"
                }
              ]
            }
          ]
        )

        # Verify second response
        refute_nil second_message

        # Drain both spans at once
        spans = rig.drain
        assert_equal 2, spans.length, "Should have created 2 spans"

        first_span = spans[0]
        second_span = spans[1]

        # Verify both spans were created
        assert_equal "anthropic.messages.create", first_span.name
        assert_equal "anthropic.messages.create", second_span.name

        # Verify second span has tool_result in input
        assert second_span.attributes.key?("braintrust.input_json")
        second_input = JSON.parse(second_span.attributes["braintrust.input_json"])
        assert_equal 3, second_input.length
        # Check that tool_result is in the last message
        assert second_input[2]["content"].is_a?(Array)
        assert second_input[2]["content"].any? { |c| c["type"] == "tool_result" }
      else
        # If model didn't use tool, just verify the span was created
        first_span = rig.drain_one
        assert_equal "anthropic.messages.create", first_span.name
      end
    end
  end
end
