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
