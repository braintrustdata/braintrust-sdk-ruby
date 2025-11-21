# frozen_string_literal: true

require "test_helper"

class Braintrust::Trace::GeminiTest < Minitest::Test
  def setup
    # Skip all Gemini tests if the gem is not available
    skip "Gemini gem not available" unless defined?(Gemini)

    @api_key = ENV["GOOGLE_API_KEY"]
    @original_api_key = ENV["GOOGLE_API_KEY"]
  end

  def teardown
    if @original_api_key
      ENV["GOOGLE_API_KEY"] = @original_api_key
    else
      ENV.delete("GOOGLE_API_KEY")
    end
  end

  def test_wrap_creates_span_for_basic_generate_content
    VCR.use_cassette("gemini/basic_generate_content") do
      require "gemini-ai"

      # Set up test rig (includes Braintrust processor)
      rig = setup_otel_test_rig

      # Create Gemini client and wrap it with Braintrust tracing
      client = Gemini.new(
        credentials: {
          service: "generative-language-api",
          api_key: @api_key
        },
        options: {model: "gemini-pro"}
      )
      Braintrust::Trace::Gemini.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a simple generate_content request
      result = client.generate_content({
        contents: {role: "user", parts: {text: "Say 'test'"}}
      })

      # Verify response
      refute_nil result
      assert result.is_a?(Array)
      assert result.length > 0
      assert result[0].key?("candidates")

      # Drain and verify span
      span = rig.drain_one

      # Verify span name matches pattern
      assert_equal "gemini.generate_content", span.name

      # Verify braintrust.input_json contains messages
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]
      assert_equal "Say 'test'", input[0]["parts"][0]["text"]

      # Verify braintrust.output_json contains response as message array
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal "model", output[0]["role"]
      assert output[0]["parts"].is_a?(Array)

      # Verify braintrust.metadata contains request and response metadata
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "gemini", metadata["provider"]
      assert_equal "/generateContent", metadata["endpoint"]
      assert_equal "gemini-pro", metadata["model"]

      # Verify braintrust.metrics contains token usage
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics["tokens"] > 0
      assert_equal metrics["prompt_tokens"] + metrics["completion_tokens"], metrics["tokens"]
    end
  end

  def test_wrap_handles_streaming_generate_content
    VCR.use_cassette("gemini/streaming_generate_content") do
      require "gemini-ai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Gemini client and wrap it
      client = Gemini.new(
        credentials: {
          service: "generative-language-api",
          api_key: @api_key
        },
        options: {model: "gemini-pro", server_sent_events: true}
      )
      Braintrust::Trace::Gemini.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a streaming request
      result = client.stream_generate_content({
        contents: {role: "user", parts: {text: "Count to 5"}}
      })

      # Verify result is an array
      refute_nil result
      assert result.is_a?(Array)

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "gemini.generate_content", span.name

      # Verify braintrust.input_json
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]

      # Verify braintrust.output_json contains aggregated response
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal "model", output[0]["role"]

      # Verify metadata has stream flag
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "gemini", metadata["provider"]
      assert_equal true, metadata["stream"]
    end
  end

  def test_wrap_handles_multimodal_content
    VCR.use_cassette("gemini/multimodal_content") do
      require "gemini-ai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Gemini client and wrap it
      client = Gemini.new(
        credentials: {
          service: "generative-language-api",
          api_key: @api_key
        },
        options: {model: "gemini-pro-vision"}
      )
      Braintrust::Trace::Gemini.wrap(client, tracer_provider: rig.tracer_provider)

      # Make a multimodal request with text and image
      result = client.generate_content({
        contents: {
          role: "user",
          parts: [
            {text: "What's in this image?"},
            {
              inline_data: {
                mime_type: "image/jpeg",
                data: "base64encodedimagedata"
              }
            }
          ]
        }
      })

      # Verify response
      refute_nil result

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "gemini.generate_content", span.name

      # Verify input contains both text and image parts
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal 2, input[0]["parts"].length
    end
  end

  def test_wrap_handles_errors
    VCR.use_cassette("gemini/error") do
      require "gemini-ai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Create Gemini client with invalid API key
      client = Gemini.new(
        credentials: {
          service: "generative-language-api",
          api_key: "invalid-key"
        },
        options: {model: "gemini-pro"}
      )
      Braintrust::Trace::Gemini.wrap(client, tracer_provider: rig.tracer_provider)

      # Expect an error
      assert_raises StandardError do
        client.generate_content({
          contents: {role: "user", parts: {text: "test"}}
        })
      end

      # Drain and verify span has error status
      span = rig.drain_one

      # Verify span name
      assert_equal "gemini.generate_content", span.name

      # Verify span has error status
      assert_equal OpenTelemetry::Trace::Status::ERROR, span.status.code
    end
  end
end
