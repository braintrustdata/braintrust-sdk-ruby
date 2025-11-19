# frozen_string_literal: true

require "test_helper"

class Braintrust::Trace::RubyLLMTest < Minitest::Test
  def setup
    # Skip all RubyLLM tests if the gem is not available
    skip "RubyLLM gem not available" unless defined?(RubyLLM)

    @api_key = ENV["OPENAI_API_KEY"]
    @original_api_key = ENV["OPENAI_API_KEY"]
  end

  def teardown
    if @original_api_key
      ENV["OPENAI_API_KEY"] = @original_api_key
    else
      ENV.delete("OPENAI_API_KEY")
    end
  end

  def test_wrap_creates_span_for_basic_chat
    VCR.use_cassette("ruby_llm/basic_chat") do
      require "ruby_llm"

      # Set up test rig (includes Braintrust processor)
      rig = setup_otel_test_rig

      # Configure RubyLLM
      RubyLLM.configure do |config|
        config.openai_api_key = @api_key
      end

      # Create chat instance and wrap it with Braintrust tracing
      chat = RubyLLM.chat(model: "gpt-4o-mini")
      Braintrust::Trace::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)

      # Make a simple chat request
      response = chat.ask("Say 'test'")

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
      assert input.is_a?(Array)
      assert input.length > 0

      # Verify braintrust.output_json contains response
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      refute_nil output

      # Verify braintrust.metadata contains provider and model info
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "ruby_llm", metadata["provider"]
      assert_equal "gpt-4o-mini", metadata["model"]

      # Verify braintrust.metrics contains token usage
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics["tokens"] > 0
    end
  end

  def test_wrap_creates_span_for_streaming_chat
    VCR.use_cassette("ruby_llm/streaming_chat") do
      require "ruby_llm"

      # Set up test rig
      rig = setup_otel_test_rig

      # Configure RubyLLM
      RubyLLM.configure do |config|
        config.openai_api_key = @api_key
      end

      # Create chat instance and wrap it
      chat = RubyLLM.chat(model: "gpt-4o-mini")
      Braintrust::Trace::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)

      # Make a streaming chat request
      chunks = []
      chat.ask("Count to 3") do |chunk|
        chunks << chunk
      end

      # Verify chunks were received
      refute_empty chunks

      # Drain and verify span
      span = rig.drain_one

      # Verify span name (same for streaming and non-streaming)
      assert_equal "ruby_llm.chat.ask", span.name

      # Verify input
      assert span.attributes.key?("braintrust.input_json")

      # Verify output was aggregated
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      refute_nil output

      # Verify metadata
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "ruby_llm", metadata["provider"]
      assert_equal true, metadata["stream"]
    end
  end
end
