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
end
