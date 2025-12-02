# frozen_string_literal: true

require "test_helper"

class Braintrust::Trace::OpenAITest < Minitest::Test
  def setup
    # Skip all OpenAI tests if the gem is not available
    skip "OpenAI gem not available" unless defined?(OpenAI)

    # Check which gem is loaded by looking at Gem.loaded_specs
    # ruby-openai has gem name "ruby-openai"
    # official openai gem has gem name "openai"
    if Gem.loaded_specs["ruby-openai"]
      skip "openai gem not available (found ruby-openai gem instead)"
    elsif !Gem.loaded_specs["openai"]
      skip "Could not determine which OpenAI gem is loaded"
    end
  end

  def test_wrap_creates_span_for_chat_completions
    VCR.use_cassette("openai/chat_completions") do
      require "openai"

      # Set up test rig (includes Braintrust processor)
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it with Braintrust tracing
      client = OpenAI::Client.new(api_key: get_openai_key)
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
      assert_equal "Chat Completion", span.name

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
      client = OpenAI::Client.new(api_key: get_openai_key)
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
      assert_equal "Chat Completion", span.name

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
      client = OpenAI::Client.new(api_key: get_openai_key)
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
      client = OpenAI::Client.new(api_key: get_openai_key)
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
      client = OpenAI::Client.new(api_key: get_openai_key)
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
      assert_equal "Chat Completion", span.name

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
      client = OpenAI::Client.new(api_key: get_openai_key)
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
      assert_equal "Chat Completion", span.name

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
      assert_equal "Chat Completion", span.name

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
      assert_equal "Chat Completion", span.name

      # Verify span status indicates an error
      assert_equal OpenTelemetry::Trace::Status::ERROR, span.status.code

      # Verify error message is captured in status description
      refute_nil span.status.description

      # Verify exception event was recorded
      assert span.events.any? { |event| event.name == "exception" }, "Should have an exception event"
    end
  end

  def test_wrap_responses_create_non_streaming
    require "openai"

    VCR.use_cassette("openai_responses_create_non_streaming") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Skip if responses API not available
      skip "Responses API not available in this OpenAI gem version" unless client.respond_to?(:responses)

      # Make a non-streaming responses.create request
      response = client.responses.create(
        model: "gpt-4o-mini",
        instructions: "You are a helpful assistant.",
        input: "What is 2+2?"
      )

      # Verify response
      refute_nil response
      refute_nil response.output

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "openai.responses.create", span.name

      # Verify braintrust.input_json contains input
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal "What is 2+2?", input

      # Verify braintrust.output_json contains output
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      refute_nil output

      # Verify braintrust.metadata contains request metadata
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal "/v1/responses", metadata["endpoint"]
      assert_equal "gpt-4o-mini", metadata["model"]
      assert_equal "You are a helpful assistant.", metadata["instructions"]

      # Verify braintrust.metrics contains token usage
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["tokens"] > 0 if metrics["tokens"]
    end
  end

  def test_wrap_responses_create_streaming
    require "openai"

    VCR.use_cassette("openai_responses_create_streaming") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Skip if responses API not available
      skip "Responses API not available in this OpenAI gem version" unless client.respond_to?(:responses)

      # Make a streaming responses request using .stream method
      stream = client.responses.stream(
        model: "gpt-4o-mini",
        input: "Count from 1 to 3"
      )

      # Consume the stream
      event_count = 0
      stream.each do |event|
        event_count += 1
      end

      # Verify we got events
      assert event_count > 0, "Should have received streaming events"

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "openai.responses.create", span.name

      # Verify input was captured
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal "Count from 1 to 3", input

      # Verify output was aggregated from stream
      assert span.attributes.key?("braintrust.output_json"), "Missing braintrust.output_json. Keys: #{span.attributes.keys}"
      output = JSON.parse(span.attributes["braintrust.output_json"])
      refute_nil output, "Output is nil: #{output.inspect}"

      # Verify metadata includes stream flag
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal "/v1/responses", metadata["endpoint"]
      assert_equal true, metadata["stream"]

      # Verify metrics were captured if available
      if span.attributes.key?("braintrust.metrics")
        metrics = JSON.parse(span.attributes["braintrust.metrics"])
        assert metrics["tokens"] > 0 if metrics["tokens"]
      end
    end
  end

  def test_wrap_responses_stream_partial_consumption
    require "openai"

    VCR.use_cassette("openai_responses_stream_partial") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Skip if responses API not available
      skip "Responses API not available in this OpenAI gem version" unless client.respond_to?(:responses)

      # Make a streaming request
      stream = client.responses.stream(
        model: "gpt-4o-mini",
        input: "Count from 1 to 10"
      )

      # Consume only part of the stream
      event_count = 0
      begin
        stream.each do |event|
          event_count += 1
          break if event_count >= 3  # Stop after 3 events
        end
      rescue StopIteration
        # Expected when breaking out of iteration
      end

      # Span should be finished even though we didn't consume all events
      span = rig.drain_one

      # Verify span name
      assert_equal "openai.responses.create", span.name

      # Verify input was captured
      assert span.attributes.key?("braintrust.input_json")
    end
  end

  def test_chat_and_responses_do_not_interfere
    require "openai"

    # This test verifies that chat completions and responses API can coexist
    # without interfering with each other when both wrappers are active
    VCR.use_cassette("openai_chat_and_responses_no_interference") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it (wraps BOTH chat and responses)
      client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Skip if responses API not available
      skip "Responses API not available in this OpenAI gem version" unless client.respond_to?(:responses)

      # First, make a chat completion request
      chat_response = client.chat.completions.create(
        messages: [{role: "user", content: "Say hello"}],
        model: "gpt-4o-mini",
        max_tokens: 10
      )
      refute_nil chat_response

      # Then, make a responses API request
      # This is where the bug would manifest if the wrappers interfere
      responses_response = client.responses.create(
        model: "gpt-4o-mini",
        instructions: "You are a helpful assistant.",
        input: "Say goodbye"
      )
      refute_nil responses_response
      refute_nil responses_response.output

      # Drain both spans
      spans = rig.drain
      assert_equal 2, spans.length, "Should have 2 spans (chat + responses)"

      # Verify first span is for chat completions
      chat_span = spans[0]
      assert_equal "Chat Completion", chat_span.name
      chat_metadata = JSON.parse(chat_span.attributes["braintrust.metadata"])
      assert_equal "/v1/chat/completions", chat_metadata["endpoint"]
      assert_equal "gpt-4o-mini", chat_metadata["model"]

      # Verify input is messages array (chat API structure)
      chat_input = JSON.parse(chat_span.attributes["braintrust.input_json"])
      assert_instance_of Array, chat_input
      assert_equal "user", chat_input[0]["role"]
      assert_equal "Say hello", chat_input[0]["content"]

      responses_span = spans[1]
      assert_equal "openai.responses.create", responses_span.name

      responses_metadata = JSON.parse(responses_span.attributes["braintrust.metadata"])
      assert_equal "/v1/responses", responses_metadata["endpoint"]
      assert_equal "gpt-4o-mini", responses_metadata["model"]
      assert_equal "You are a helpful assistant.", responses_metadata["instructions"]

      responses_input = JSON.parse(responses_span.attributes["braintrust.input_json"])
      assert_equal "Say goodbye", responses_input
    end
  end

  def test_streaming_chat_and_responses_do_not_interfere
    require "openai"

    # This test verifies that streaming for both chat completions and responses API
    # work correctly without interfering when both streaming wrappers are active.
    # This is critical because streaming uses different aggregation mechanisms.
    VCR.use_cassette("openai_streaming_chat_and_responses_no_interference") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it (wraps BOTH chat and responses)
      client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Skip if responses API not available
      skip "Responses API not available in this OpenAI gem version" unless client.respond_to?(:responses)

      # First, make a STREAMING chat completion request
      chat_content = ""
      stream = client.chat.completions.stream_raw(
        messages: [{role: "user", content: "Count from 1 to 3"}],
        model: "gpt-4o-mini",
        max_tokens: 50,
        stream_options: {include_usage: true}
      )
      stream.each do |chunk|
        delta_content = chunk.choices[0]&.delta&.content
        chat_content += delta_content if delta_content
      end
      refute_empty chat_content

      # Then, make a STREAMING responses API request
      # This is where the bug would manifest if streaming wrappers interfere
      responses_event_count = 0
      responses_stream = client.responses.stream(
        model: "gpt-4o-mini",
        instructions: "You are a helpful assistant.",
        input: "Say hello"
      )
      responses_stream.each do |event|
        responses_event_count += 1
      end
      assert responses_event_count > 0, "Should have received streaming events from responses API"

      # Drain both spans
      spans = rig.drain
      assert_equal 2, spans.length, "Should have 2 spans (chat streaming + responses streaming)"

      # Verify first span is for STREAMING chat completions
      chat_span = spans[0]
      assert_equal "Chat Completion", chat_span.name
      chat_metadata = JSON.parse(chat_span.attributes["braintrust.metadata"])
      assert_equal "/v1/chat/completions", chat_metadata["endpoint"]
      assert_equal true, chat_metadata["stream"], "Chat span should have stream flag"
      assert_match(/gpt-4o-mini/, chat_metadata["model"])

      # Verify chat input is messages array (chat API structure)
      chat_input = JSON.parse(chat_span.attributes["braintrust.input_json"])
      assert_instance_of Array, chat_input
      assert_equal "user", chat_input[0]["role"]
      assert_equal "Count from 1 to 3", chat_input[0]["content"]

      # Verify chat output was aggregated from stream chunks
      chat_output = JSON.parse(chat_span.attributes["braintrust.output_json"])
      assert_equal 1, chat_output.length
      assert_equal "assistant", chat_output[0]["message"]["role"]
      refute_nil chat_output[0]["message"]["content"]
      assert chat_output[0]["message"]["content"].length > 0, "Chat content should be aggregated"

      responses_span = spans[1]
      assert_equal "openai.responses.create", responses_span.name

      responses_metadata = JSON.parse(responses_span.attributes["braintrust.metadata"])
      assert_equal "/v1/responses", responses_metadata["endpoint"]
      assert_equal true, responses_metadata["stream"]
      assert_match(/gpt-4o-mini/, responses_metadata["model"])
      assert_equal "You are a helpful assistant.", responses_metadata["instructions"]

      responses_input = JSON.parse(responses_span.attributes["braintrust.input_json"])
      assert_equal "Say hello", responses_input

      assert responses_span.attributes.key?("braintrust.output_json")
      responses_output = JSON.parse(responses_span.attributes["braintrust.output_json"])
      refute_nil responses_output
    end
  end

  def test_traced_vs_raw_chat_completions_non_streaming
    require "openai"

    # This test verifies that tracing doesn't mutate the response
    # by comparing output from a raw client vs a traced client
    VCR.use_cassette("openai_traced_vs_raw_chat_non_streaming") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create two clients: one raw, one traced
      raw_client = OpenAI::Client.new(api_key: get_openai_key)
      traced_client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(traced_client, tracer_provider: rig.tracer_provider)

      # Make identical requests
      params = {
        messages: [{role: "user", content: "Say hello"}],
        model: "gpt-4o-mini",
        max_tokens: 10
      }

      raw_response = raw_client.chat.completions.create(**params)
      traced_response = traced_client.chat.completions.create(**params)

      assert_match(/gpt-4o-mini/, raw_response.model)
      assert_match(/gpt-4o-mini/, traced_response.model)
      assert_equal raw_response.choices.length, traced_response.choices.length
      assert_equal raw_response.choices[0].message.role, traced_response.choices[0].message.role
      refute_nil raw_response.choices[0].message.content
      refute_nil traced_response.choices[0].message.content
      assert_equal raw_response.choices[0].finish_reason, traced_response.choices[0].finish_reason
      assert_operator raw_response.usage.total_tokens, :>, 0
      assert_operator traced_response.usage.total_tokens, :>, 0

      spans = rig.drain
      assert_equal 1, spans.length
      assert_equal "Chat Completion", spans[0].name
    end
  end

  def test_traced_vs_raw_chat_completions_streaming
    require "openai"

    # This test verifies that tracing doesn't mutate streaming responses
    VCR.use_cassette("openai_traced_vs_raw_chat_streaming") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create two clients: one raw, one traced
      raw_client = OpenAI::Client.new(api_key: get_openai_key)
      traced_client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(traced_client, tracer_provider: rig.tracer_provider)

      # Make identical streaming requests
      params = {
        messages: [{role: "user", content: "Count from 1 to 3"}],
        model: "gpt-4o-mini",
        max_tokens: 50,
        stream_options: {include_usage: true}
      }

      raw_chunks = []
      raw_stream = raw_client.chat.completions.stream_raw(**params)
      raw_stream.each do |chunk|
        raw_chunks << chunk
      end

      traced_chunks = []
      traced_stream = traced_client.chat.completions.stream_raw(**params)
      traced_stream.each do |chunk|
        traced_chunks << chunk
      end

      assert_operator (raw_chunks.length - traced_chunks.length).abs, :<=, 2
      if raw_chunks[0].respond_to?(:model) && traced_chunks[0].respond_to?(:model)
        assert_match(/gpt-4o-mini/, raw_chunks[0].model)
        assert_match(/gpt-4o-mini/, traced_chunks[0].model)
      end

      raw_content = raw_chunks.map { |c| c.choices[0]&.delta&.content }.compact.join
      traced_content = traced_chunks.map { |c| c.choices[0]&.delta&.content }.compact.join
      refute_empty raw_content
      refute_empty traced_content

      spans = rig.drain
      assert_equal 1, spans.length
      assert_equal "Chat Completion", spans[0].name
    end
  end

  def test_traced_vs_raw_responses_non_streaming
    require "openai"

    # This test verifies that tracing doesn't mutate responses API output
    VCR.use_cassette("openai_traced_vs_raw_responses_non_streaming") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create two clients: one raw, one traced
      raw_client = OpenAI::Client.new(api_key: get_openai_key)
      traced_client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(traced_client, tracer_provider: rig.tracer_provider)

      # Skip if responses API not available
      skip "Responses API not available in this OpenAI gem version" unless raw_client.respond_to?(:responses)

      # Make identical requests
      params = {
        model: "gpt-4o-mini",
        instructions: "You are a helpful assistant.",
        input: "Say hello"
      }

      raw_response = raw_client.responses.create(**params)
      traced_response = traced_client.responses.create(**params)

      assert_match(/gpt-4o-mini/, raw_response.model)
      assert_match(/gpt-4o-mini/, traced_response.model)
      assert_equal raw_response.output.length, traced_response.output.length

      raw_output = raw_response.output.first.content.first
      traced_output = traced_response.output.first.content.first
      assert_equal raw_output[:type], traced_output[:type]
      refute_nil raw_output[:text]
      refute_nil traced_output[:text]
      assert_operator raw_output[:text].length, :>, 0
      assert_operator traced_output[:text].length, :>, 0

      assert_operator raw_response.usage.total_tokens, :>, 0
      assert_operator traced_response.usage.total_tokens, :>, 0

      spans = rig.drain
      assert_equal 1, spans.length
      assert_equal "openai.responses.create", spans[0].name
    end
  end

  def test_traced_vs_raw_responses_streaming
    require "openai"

    # This test verifies that tracing doesn't mutate responses API streaming
    VCR.use_cassette("openai_traced_vs_raw_responses_streaming") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create two clients: one raw, one traced
      raw_client = OpenAI::Client.new(api_key: get_openai_key)
      traced_client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(traced_client, tracer_provider: rig.tracer_provider)

      # Skip if responses API not available
      skip "Responses API not available in this OpenAI gem version" unless raw_client.respond_to?(:responses)

      params = {
        model: "gpt-4o-mini",
        instructions: "You are a helpful assistant.",
        input: "Count from 1 to 3"
      }

      raw_events = []
      raw_stream = raw_client.responses.stream(**params)
      raw_stream.each do |event|
        raw_events << event
      end

      traced_events = []
      traced_stream = traced_client.responses.stream(**params)
      traced_stream.each do |event|
        traced_events << event
      end

      assert_equal raw_events.length, traced_events.length

      raw_event_types = raw_events.map(&:type)
      traced_event_types = traced_events.map(&:type)
      assert_equal raw_event_types, traced_event_types

      raw_completed = raw_events.find { |e| e.type == "response.completed" }
      traced_completed = traced_events.find { |e| e.type == "response.completed" }

      if raw_completed && traced_completed
        assert_match(/gpt-4o-mini/, raw_completed.response.model)
        assert_match(/gpt-4o-mini/, traced_completed.response.model)
        assert_operator raw_completed.response.usage.total_tokens, :>, 0
        assert_operator traced_completed.response.usage.total_tokens, :>, 0
      end

      spans = rig.drain
      assert_equal 1, spans.length
      assert_equal "openai.responses.create", spans[0].name
    end
  end

  def test_wrap_handles_streaming_with_text
    VCR.use_cassette("openai/streaming_text") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a streaming request using .stream (not .stream_raw)
      stream = client.chat.completions.stream(
        messages: [
          {role: "user", content: "Count from 1 to 3"}
        ],
        model: "gpt-4o-mini",
        max_tokens: 50,
        stream_options: {
          include_usage: true
        }
      )

      # Consume the stream using .text() method
      full_text = ""
      stream.text.each do |delta|
        full_text += delta
      end

      # Verify we got content
      refute_empty full_text

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "Chat Completion", span.name

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
      assert_match(/gpt-4o-mini/, metadata["model"])

      # Verify metrics were captured (if include_usage was respected)
      if span.attributes.key?("braintrust.metrics")
        metrics = JSON.parse(span.attributes["braintrust.metrics"])
        assert metrics["tokens"] > 0 if metrics["tokens"]
      end
    end
  end

  def test_wrap_handles_streaming_with_get_final_completion
    VCR.use_cassette("openai/streaming_get_final_completion") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a streaming request using .stream
      stream = client.chat.completions.stream(
        messages: [
          {role: "user", content: "Say hello"}
        ],
        model: "gpt-4o-mini",
        max_tokens: 20,
        stream_options: {
          include_usage: true
        }
      )

      # Use .get_final_completion() to block and get final result
      completion = stream.get_final_completion

      # Verify we got a completion
      refute_nil completion
      refute_nil completion.choices
      assert completion.choices.length > 0
      refute_nil completion.choices[0].message.content

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "Chat Completion", span.name

      # Verify output was captured
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert output[0]["message"]["content"], "Should have captured content"
    end
  end

  def test_wrap_handles_streaming_with_get_output_text
    VCR.use_cassette("openai/streaming_get_output_text") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust::Trace::OpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a streaming request using .stream
      stream = client.chat.completions.stream(
        messages: [
          {role: "user", content: "Say hello"}
        ],
        model: "gpt-4o-mini",
        max_tokens: 20,
        stream_options: {
          include_usage: true
        }
      )

      # Use .get_output_text() to block and get final text
      output_text = stream.get_output_text

      # Verify we got text
      refute_nil output_text
      refute_empty output_text

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "Chat Completion", span.name

      # Verify output was captured
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert output[0]["message"]["content"], "Should have captured content"
    end
  end
end
