# frozen_string_literal: true

require "test_helper"

class Braintrust::Trace::OpenAITest < Minitest::Test
  def setup
    @api_key = ENV["OPENAI_API_KEY"]
    skip "OPENAI_API_KEY environment variable is required for OpenAI tests" unless @api_key

    @original_api_key = ENV["OPENAI_API_KEY"]
  end

  def teardown
    if @original_api_key
      ENV["OPENAI_API_KEY"] = @original_api_key
    else
      ENV.delete("OPENAI_API_KEY")
    end
  end

  def test_wrap_creates_span_for_chat_completions
    VCR.use_cassette("openai/chat_completions") do
      require "openai"

      # Set up test rig (includes Braintrust processor)
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it with Braintrust tracing
      client = OpenAI::Client.new(api_key: @api_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a simple chat completion request with additional params to test metadata capture
      response = client.chat.completions.create(
        messages: [
          {role: "system", content: "You are a test assistant."},
          {role: "user", content: "Say 'test'"}
        ],
        model: "gpt-4o-mini",
        max_tokens: 10,
        temperature: 0.5
      )

      # Verify response
      refute_nil response
      refute_nil response.choices[0].message.content

      # Drain and verify span
      span = rig.drain_one

      # Verify span name matches Go SDK
      assert_equal "openai.chat.completions.create", span.name

      # Verify braintrust.input_json contains messages
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 2, input.length
      assert_equal "system", input[0]["role"]
      assert_equal "You are a test assistant.", input[0]["content"]
      assert_equal "user", input[1]["role"]
      assert_equal "Say 'test'", input[1]["content"]

      # Verify braintrust.output_json contains choices
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
      assert_equal "gpt-4o-mini", metadata["model"]
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
    end
  end

  def test_wrap_handles_vision_messages_with_image_url
    VCR.use_cassette("openai/vision") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: @api_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a vision request with content array (image_url + text)
      response = client.chat.completions.create(
        messages: [
          {
            role: "user",
            content: [
              {type: "text", text: "What color is this image?"},
              {
                type: "image_url",
                image_url: {
                  url: "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/320px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"
                }
              }
            ]
          }
        ],
        model: "gpt-4o-mini",
        max_tokens: 50
      )

      # Verify response
      refute_nil response
      refute_nil response.choices[0].message.content

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "openai.chat.completions.create", span.name

      # Verify braintrust.input_json contains messages with content array
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]

      # Content should be an array, not a string
      assert_instance_of Array, input[0]["content"]
      assert_equal 2, input[0]["content"].length

      # First element should be text
      assert_equal "text", input[0]["content"][0]["type"]
      assert_equal "What color is this image?", input[0]["content"][0]["text"]

      # Second element should be image_url
      assert_equal "image_url", input[0]["content"][1]["type"]
      assert input[0]["content"][1]["image_url"].key?("url")
      assert_match(/wikimedia/, input[0]["content"][1]["image_url"]["url"])

      # Verify output still works
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      refute_nil output[0]["message"]["content"]
    end
  end

  def test_wrap_handles_tool_messages_with_tool_call_id
    VCR.use_cassette("openai/tool_messages") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: @api_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # First request - model will use a tool
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

      first_response = client.chat.completions.create(
        messages: [
          {role: "user", content: "What's the weather in Paris?"}
        ],
        model: "gpt-4o-mini",
        tools: tools,
        max_tokens: 100
      )

      # Get the tool call from response
      tool_call = first_response.choices[0].message.tool_calls&.first
      skip "Model didn't call tool" unless tool_call

      # Second request - provide tool result with tool_call_id
      second_response = client.chat.completions.create(
        messages: [
          {role: "user", content: "What's the weather in Paris?"},
          {
            role: "assistant",
            content: nil,
            tool_calls: [
              {
                id: tool_call.id,
                type: "function",
                function: {
                  name: tool_call.function.name,
                  arguments: tool_call.function.arguments
                }
              }
            ]
          },
          {
            role: "tool",
            tool_call_id: tool_call.id,
            content: "Sunny, 22°C"
          }
        ],
        model: "gpt-4o-mini",
        tools: tools,
        max_tokens: 100
      )

      # Verify response
      refute_nil second_response
      refute_nil second_response.choices[0].message.content

      # Drain all spans (we have 2: first request + second request)
      spans = rig.drain
      assert_equal 2, spans.length, "Should have 2 spans (one for each request)"

      # We're testing the second span (second request)
      span = spans[1]

      # Verify braintrust.input_json contains all message fields
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 3, input.length

      # First message: user
      assert_equal "user", input[0]["role"]
      assert_equal "What's the weather in Paris?", input[0]["content"]

      # Second message: assistant with tool_calls
      assert_equal "assistant", input[1]["role"]
      assert input[1].key?("tool_calls"), "assistant message should have tool_calls"
      assert_equal 1, input[1]["tool_calls"].length
      assert_equal tool_call.id, input[1]["tool_calls"][0]["id"]
      assert_equal "function", input[1]["tool_calls"][0]["type"]
      assert_equal tool_call.function.name, input[1]["tool_calls"][0]["function"]["name"]

      # Third message: tool response with tool_call_id
      assert_equal "tool", input[2]["role"]
      assert_equal tool_call.id, input[2]["tool_call_id"], "tool message should preserve tool_call_id"
      assert_equal "Sunny, 22°C", input[2]["content"]

      # Verify output contains tool_calls
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      refute_nil output[0]["message"]["content"]
    end
  end

  def test_wrap_parses_advanced_token_metrics
    VCR.use_cassette("openai/advanced_tokens") do
      require "openai"

      # This test verifies that we properly parse token_details fields
      # Note: We're testing with a mock since we can't control what OpenAI returns

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: @api_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a request (ideally with a model that returns detailed metrics)
      # For now, we'll just make a normal request and verify the metrics structure
      response = client.chat.completions.create(
        messages: [
          {role: "user", content: "test"}
        ],
        model: "gpt-4o-mini",
        max_tokens: 10
      )

      # Verify response
      refute_nil response

      # Drain and verify span
      span = rig.drain_one

      # Verify braintrust.metrics exists
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])

      # Basic metrics should always be present
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics["tokens"] > 0

      # If the response includes token_details, they should be parsed with correct naming
      # The response.usage object may have:
      # - prompt_tokens_details.cached_tokens → prompt_cached_tokens
      # - prompt_tokens_details.audio_tokens → prompt_audio_tokens
      # - completion_tokens_details.reasoning_tokens → completion_reasoning_tokens
      # - completion_tokens_details.audio_tokens → completion_audio_tokens
      #
      # We can't force OpenAI to return these, but if they exist, we verify the naming

      if response.usage.respond_to?(:prompt_tokens_details) && response.usage.prompt_tokens_details
        details = response.usage.prompt_tokens_details
        if details.respond_to?(:cached_tokens) && details.cached_tokens
          assert metrics.key?("prompt_cached_tokens"), "Should have prompt_cached_tokens"
          assert_equal details.cached_tokens, metrics["prompt_cached_tokens"]
        end
      end

      if response.usage.respond_to?(:completion_tokens_details) && response.usage.completion_tokens_details
        details = response.usage.completion_tokens_details
        if details.respond_to?(:reasoning_tokens) && details.reasoning_tokens
          assert metrics.key?("completion_reasoning_tokens"), "Should have completion_reasoning_tokens"
          assert_equal details.reasoning_tokens, metrics["completion_reasoning_tokens"]
        end
      end
    end
  end

  def test_wrap_handles_streaming_chat_completions
    VCR.use_cassette("openai/streaming") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: @api_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a streaming request
      stream = client.chat.completions.stream_raw(
        messages: [
          {role: "user", content: "Count from 1 to 3"}
        ],
        model: "gpt-4o-mini",
        max_tokens: 50,
        stream_options: {
          include_usage: true  # Request usage stats in stream
        }
      )

      # Consume the stream
      full_content = ""
      stream.each do |chunk|
        delta_content = chunk.choices[0]&.delta&.content
        full_content += delta_content if delta_content
      end

      # Verify we got content
      refute_empty full_content

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "openai.chat.completions.create", span.name

      # Verify input was captured
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]
      assert_equal "Count from 1 to 3", input[0]["content"]

      # Verify output was aggregated from stream
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal 0, output[0]["index"]
      assert_equal "assistant", output[0]["message"]["role"]
      assert output[0]["message"]["content"], "Should have aggregated content"
      assert output[0]["message"]["content"].length > 0, "Content should not be empty"

      # Verify metadata includes stream flag
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal true, metadata["stream"]
      assert_match(/gpt-4o-mini/, metadata["model"])  # Model may include version suffix

      # Verify metrics were captured (if include_usage was respected)
      if span.attributes.key?("braintrust.metrics")
        metrics = JSON.parse(span.attributes["braintrust.metrics"])
        assert metrics["tokens"] > 0 if metrics["tokens"]
      end
    end
  end

  def test_wrap_closes_span_for_partially_consumed_stream
    VCR.use_cassette("openai/partial_stream") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: @api_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a streaming request
      stream = client.chat.completions.stream_raw(
        messages: [
          {role: "user", content: "Count from 1 to 10"}
        ],
        model: "gpt-4o-mini",
        max_tokens: 50
      )

      # Consume only part of the stream
      chunk_count = 0
      begin
        stream.each do |chunk|
          chunk_count += 1
          break if chunk_count >= 2  # Stop after 2 chunks
        end
      rescue StopIteration
        # Expected when breaking out of iteration
      end

      # Span should be finished even though we didn't consume all chunks
      span = rig.drain_one

      # Verify span name
      assert_equal "openai.chat.completions.create", span.name

      # Verify input was captured
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length

      # Note: output will be partially aggregated
    end
  end

  def test_wrap_records_exception_for_create_errors
    VCR.use_cassette("openai/create_error") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client with invalid API key to trigger an error
      client = OpenAI::Client.new(api_key: "invalid_key")
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a request that will fail
      error = assert_raises do
        client.chat.completions.create(
          messages: [
            {role: "user", content: "test"}
          ],
          model: "gpt-4o-mini"
        )
      end

      # Verify an error was raised
      refute_nil error

      # Drain and verify span was created with error information
      span = rig.drain_one

      # Verify span name
      assert_equal "openai.chat.completions.create", span.name

      # Verify span status indicates an error
      assert_equal OpenTelemetry::Trace::Status::ERROR, span.status.code

      # Verify error message is captured in status description
      refute_nil span.status.description
      assert span.status.description.length > 0

      # Verify exception event was recorded
      assert span.events.any? { |event| event.name == "exception" }, "Should have an exception event"

      exception_event = span.events.find { |event| event.name == "exception" }
      assert exception_event.attributes.key?("exception.type"), "Should have exception type"
      assert exception_event.attributes.key?("exception.message"), "Should have exception message"
    end
  end

  def test_wrap_records_exception_for_stream_errors
    VCR.use_cassette("openai/stream_error") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client with invalid API key to trigger an error
      client = OpenAI::Client.new(api_key: "invalid_key")
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a streaming request that will fail
      error = assert_raises do
        stream = client.chat.completions.stream_raw(
          messages: [
            {role: "user", content: "test"}
          ],
          model: "gpt-4o-mini"
        )

        # Error occurs when we try to consume the stream
        stream.each do |chunk|
          # Won't get here
        end
      end

      # Verify an error was raised
      refute_nil error

      # Drain and verify span was created with error information
      span = rig.drain_one

      # Verify span name
      assert_equal "openai.chat.completions.create", span.name

      # Verify span status indicates an error
      assert_equal OpenTelemetry::Trace::Status::ERROR, span.status.code

      # Verify error message is captured in status description
      refute_nil span.status.description

      # Verify exception event was recorded
      assert span.events.any? { |event| event.name == "exception" }, "Should have an exception event"
    end
  end
end
