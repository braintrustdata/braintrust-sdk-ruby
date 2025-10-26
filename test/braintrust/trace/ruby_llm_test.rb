# frozen_string_literal: true

require "test_helper"

class Braintrust::Trace::RubyLLMTest < Minitest::Test
  # Define test tool class at class level (can't be defined inside test methods)
  if defined?(RubyLLM)
    class TestWeatherTool < RubyLLM::Tool
      description "Get weather for a location"
      param :location

      def execute(location:)
        {temperature: 72, condition: "sunny", location: location}
      end
    end
  end

  def setup
    # Skip all RubyLLM tests if the gem is not available
    skip "RubyLLM gem not available" unless defined?(RubyLLM)

    @api_key = ENV["OPENAI_API_KEY"]
    @original_api_key = ENV["OPENAI_API_KEY"]

    # Debug: Check if ENV var is actually set
    puts "\n[DEBUG] OPENAI_API_KEY present: #{!ENV["OPENAI_API_KEY"].nil?}" if ENV["DEBUG_TESTS"]
  end

  def teardown
    if @original_api_key
      ENV["OPENAI_API_KEY"] = @original_api_key
    else
      # DON'T delete if we never had it - this stomps on the environment!
      # ENV.delete("OPENAI_API_KEY")
    end
  end

  def test_wrap_creates_span_for_basic_chat
    VCR.use_cassette("ruby_llm/basic_chat") do
      require "ruby_llm"

      # Configure RubyLLM with OpenAI API key
      RubyLLM.configure do |config|
        config.openai_api_key = @api_key
      end

      # Set up test rig (includes Braintrust processor)
      rig = setup_otel_test_rig

      # Create RubyLLM chat instance
      chat = RubyLLM.chat.with_model("gpt-4o-mini")

      # Wrap it with Braintrust tracing
      Braintrust::Trace::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)

      # Make a simple chat request
      response = chat.ask "Say 'test'"

      # Verify response
      refute_nil response
      refute_nil response.content
      assert response.content.length > 0

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "ruby_llm.chat.ask", span.name

      # Verify braintrust.input_json contains messages
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      # RubyLLM may include multiple messages (e.g., system + user)
      assert input.length >= 1
      # Find the user message
      user_message = input.find { |msg| msg["role"] == "user" }
      refute_nil user_message
      assert_equal "Say 'test'", user_message["content"]

      # Verify braintrust.output_json contains response as message array
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length, "Output should be an array with one message"
      assert_equal "assistant", output[0]["role"], "Output message should have assistant role"
      refute_nil output[0]["content"], "Output message should have content"

      # Verify braintrust.metadata contains provider and model info
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      # Model may include version suffix like "gpt-4o-mini-2024-07-18"
      assert metadata["model"].start_with?("gpt-4o-mini")

      # Verify braintrust.metrics contains token usage
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics["tokens"] > 0
      assert_equal metrics["prompt_tokens"] + metrics["completion_tokens"], metrics["tokens"]
    end
  end

  def test_wrap_handles_streaming
    VCR.use_cassette("ruby_llm/streaming") do
      require "ruby_llm"

      # Configure RubyLLM
      RubyLLM.configure do |config|
        config.openai_api_key = @api_key
      end

      # Set up test rig
      rig = setup_otel_test_rig

      # Create chat and wrap
      chat = RubyLLM.chat.with_model("gpt-4o-mini")
      Braintrust::Trace::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)

      # Track chunks for verification
      chunks_received = []

      # Make a streaming request
      response = chat.ask "Count to 3" do |chunk|
        chunks_received << chunk.content
      end

      # Verify we received chunks
      assert chunks_received.length > 0

      # Verify final response
      refute_nil response
      refute_nil response.content

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "ruby_llm.chat.ask", span.name

      # Verify we captured the final aggregated output (not individual chunks)
      # Output should be formatted as message array
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length, "Output should be an array with one message"
      assert_equal "assistant", output[0]["role"]
      refute_nil output[0]["content"]

      # Verify metrics are present
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
    end
  end

  def test_wrap_handles_tool_calling
    VCR.use_cassette("ruby_llm/tool_calling") do
      require "ruby_llm"

      # Configure RubyLLM
      RubyLLM.configure do |config|
        config.openai_api_key = @api_key
      end

      # Set up test rig
      rig = setup_otel_test_rig

      # Create chat with tool and wrap
      chat = RubyLLM.chat
        .with_model("gpt-4o-mini")
        .with_tool(TestWeatherTool)

      Braintrust::Trace::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)

      # Make a request that should trigger the tool
      response = chat.ask "What's the weather in Tokyo?"

      # Verify response
      refute_nil response
      refute_nil response.content

      # Drain and verify spans
      spans = rig.drain
      # Should have: 2 LLM spans (tool request + final response) + 1 tool span
      assert spans.length >= 2, "Expected at least 2 LLM spans, got #{spans.length}"

      # Find all LLM spans
      llm_spans = spans.select { |s| s.name == "ruby_llm.chat.ask" }
      assert llm_spans.length >= 2, "Expected 2 LLM spans (tool request + final response), got #{llm_spans.length}"

      # First LLM span should have tool_calls in output
      first_span = llm_spans[0]
      assert first_span.attributes.key?("braintrust.output_json"), "First span should have output"
      first_output = JSON.parse(first_span.attributes["braintrust.output_json"])
      assert_equal 1, first_output.length, "Output should be an array with one message"
      assert_equal "assistant", first_output[0]["role"]
      assert first_output[0].key?("tool_calls"), "First span output should have tool_calls"
      assert first_output[0]["tool_calls"].is_a?(Array), "tool_calls should be an array"
      assert first_output[0]["tool_calls"].length > 0, "tool_calls array should not be empty"

      # Verify tool_calls format (matching OpenAI)
      tool_call = first_output[0]["tool_calls"][0]
      assert tool_call.key?("id"), "tool_call should have id"
      assert_equal "function", tool_call["type"]
      assert tool_call.key?("function"), "tool_call should have function"
      # RubyLLM formats tool names with full class path
      assert tool_call["function"]["name"].include?("weather"), "Tool name should include 'weather'"
      assert tool_call["function"].key?("arguments"), "function should have arguments"

      # Second LLM span should have final response
      second_span = llm_spans[1]
      assert second_span.attributes.key?("braintrust.output_json"), "Second span should have output"
      second_output = JSON.parse(second_span.attributes["braintrust.output_json"])
      assert_equal 1, second_output.length
      assert_equal "assistant", second_output[0]["role"]
      assert second_output[0].key?("content"), "Final response should have content"

      # Verify second span input includes tool messages
      assert second_span.attributes.key?("braintrust.input_json"), "Second span should have input"
      second_input = JSON.parse(second_span.attributes["braintrust.input_json"])
      assert second_input.length >= 3, "Second span input should have user + assistant + tool messages"
      # Should have assistant message with tool_calls
      assistant_msg = second_input.find { |m| m["role"] == "assistant" && m.key?("tool_calls") }
      assert assistant_msg, "Input should include assistant message with tool_calls"
      # Should have tool message
      tool_msg = second_input.find { |m| m["role"] == "tool" }
      assert tool_msg, "Input should include tool result message"
      assert tool_msg.key?("tool_call_id"), "Tool message should have tool_call_id"

      # Verify tool span exists
      tool_spans = spans.select { |s| s.name.start_with?("tool:") }
      assert tool_spans.length > 0, "Should have at least one tool span"
      tool_span = tool_spans.first
      assert tool_span.name.start_with?("tool:"), "Tool span should have correct name prefix"
      # Tool span should have output
      assert tool_span.attributes.key?("braintrust.output_json"), "Tool span should have output"
    end
  end
end
