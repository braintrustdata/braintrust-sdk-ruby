# frozen_string_literal: true

require "test_helper"
require_relative "../../../../lib/braintrust/trace/contrib/github.com/alexrudall/ruby-openai/ruby-openai"

class Braintrust::Trace::AlexRudall::RubyOpenAITest < Minitest::Test
  def setup
    # Skip all ruby-openai tests if the gem is not available
    # Note: ruby-openai gem is required as "openai" (same as the openai gem)
    # We detect ruby-openai by checking the gem name in loaded specs
    begin
      require "openai"

      # Check which gem is loaded by looking at Gem.loaded_specs
      # ruby-openai has gem name "ruby-openai"
      # official openai gem has gem name "openai"
      if Gem.loaded_specs["ruby-openai"]
        @using_ruby_openai = true
      elsif Gem.loaded_specs["openai"]
        skip "ruby-openai gem not available (found openai gem instead)"
      else
        skip "Could not determine which OpenAI gem is loaded"
      end

      @gem_available = true
    rescue LoadError
      @gem_available = false
      skip "ruby-openai gem not available"
    end

    @api_key = ENV["OPENAI_API_KEY"] || "test-api-key"
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
    VCR.use_cassette("alexrudall_ruby_openai/chat_completions") do
      require "openai"

      # Set up test rig (includes Braintrust processor)
      rig = setup_otel_test_rig

      # Create OpenAI client using ruby-openai's API and wrap it with Braintrust tracing
      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust::Trace::AlexRudall::RubyOpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a simple chat completion request with additional params to test metadata capture
      # ruby-openai uses: client.chat(parameters: {...})
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

      # Verify response
      refute_nil response
      refute_nil response.dig("choices", 0, "message", "content")

      # Drain and verify span
      span = rig.drain_one

      # Verify span name matches pattern
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

      # Verify time_to_first_token metric is present
      assert metrics.key?("time_to_first_token"), "Should have time_to_first_token metric"
      assert metrics["time_to_first_token"] >= 0, "time_to_first_token should be >= 0"
    end
  end

  def test_wrap_handles_tool_calls
    VCR.use_cassette("alexrudall_ruby_openai/tool_calls") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust::Trace::AlexRudall::RubyOpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a request that will trigger a tool call
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

      # Verify response
      refute_nil response

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
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
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      refute_nil metadata["tools"]
    end
  end

  def test_wrap_handles_multi_turn_tool_calls_with_tool_call_id
    VCR.use_cassette("alexrudall_ruby_openai/multi_turn_tools") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust::Trace::AlexRudall::RubyOpenAI.wrap(client, tracer_provider: rig.tracer_provider)

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

  def test_wrap_handles_streaming_chat_completions
    VCR.use_cassette("alexrudall_ruby_openai/streaming") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust::Trace::AlexRudall::RubyOpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a streaming request with stream_options to get usage metrics
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

      # Verify output was captured and aggregated
      assert span.attributes.key?("braintrust.output_json"), "Should have braintrust.output_json"
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal 0, output[0]["index"]
      assert_equal "assistant", output[0]["message"]["role"]
      refute_nil output[0]["message"]["content"]
      refute_empty output[0]["message"]["content"]

      # Verify metadata includes stream flag
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal true, metadata["stream"]

      # Verify metrics include time_to_first_token and usage tokens
      assert span.attributes.key?("braintrust.metrics"), "Should have braintrust.metrics"
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics.key?("time_to_first_token"), "Should have time_to_first_token metric"
      assert metrics["time_to_first_token"] >= 0, "time_to_first_token should be >= 0"

      # Verify usage metrics are present (when stream_options.include_usage is set)
      assert metrics.key?("prompt_tokens"), "Should have prompt_tokens metric"
      assert metrics["prompt_tokens"] > 0, "prompt_tokens should be > 0"
      assert metrics.key?("completion_tokens"), "Should have completion_tokens metric"
      assert metrics["completion_tokens"] > 0, "completion_tokens should be > 0"
      assert metrics.key?("tokens"), "Should have tokens metric"
      assert metrics["tokens"] > 0, "tokens should be > 0"
      assert_equal metrics["prompt_tokens"] + metrics["completion_tokens"], metrics["tokens"]
    end
  end

  def test_wrap_handles_embeddings
    VCR.use_cassette("alexrudall_ruby_openai/embeddings") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust::Trace::AlexRudall::RubyOpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make an embeddings request
      response = client.embeddings(
        parameters: {
          model: "text-embedding-3-small",
          input: "The quick brown fox"
        }
      )

      # Verify response
      refute_nil response
      refute_nil response.dig("data", 0, "embedding")

      # Embeddings are not traced yet (no wrapper implemented)
      # So this should not create a span for embeddings
      # Only verify the request succeeded
      assert response.dig("data", 0, "embedding").length > 0
    end
  end

  def test_wrap_handles_completions
    VCR.use_cassette("alexrudall_ruby_openai/completions") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client and wrap it
      client = OpenAI::Client.new(access_token: @api_key)
      Braintrust::Trace::AlexRudall::RubyOpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a completions request
      response = client.completions(
        parameters: {
          model: "gpt-3.5-turbo-instruct",
          prompt: "Say hello:",
          max_tokens: 10
        }
      )

      # Verify response
      refute_nil response
      refute_nil response.dig("choices", 0, "text")

      # Completions are not traced yet (no wrapper implemented)
      # Only verify the request succeeded
      refute_empty response.dig("choices", 0, "text")
    end
  end

  def test_wrap_records_exception_for_errors
    VCR.use_cassette("alexrudall_ruby_openai/error") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create OpenAI client with invalid API key
      client = OpenAI::Client.new(access_token: "invalid_key")
      Braintrust::Trace::AlexRudall::RubyOpenAI.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a request that will fail
      error = assert_raises do
        client.chat(
          parameters: {
            model: "gpt-4o-mini",
            messages: [
              {role: "user", content: "test"}
            ]
          }
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

      # Verify error message is captured
      refute_nil span.status.description
      assert span.status.description.length > 0

      # Verify exception event was recorded
      assert span.events.any? { |event| event.name == "exception" }
    end
  end
end
