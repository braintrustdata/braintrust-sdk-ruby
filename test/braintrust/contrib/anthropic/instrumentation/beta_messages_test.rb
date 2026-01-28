# frozen_string_literal: true

require "test_helper"
require_relative "../integration_helper"

# Explicitly load the patcher (lazy-loaded by integration)
require "braintrust/contrib/anthropic/patcher"

class Braintrust::Contrib::Anthropic::Instrumentation::BetaMessagesTest < Minitest::Test
  include Braintrust::Contrib::Anthropic::IntegrationHelper

  def setup
    skip_unless_anthropic!
    skip_unless_beta_messages!
  end

  def test_creates_span_for_beta_message
    VCR.use_cassette("anthropic/beta_basic_message") do
      # Set up test rig (includes Braintrust processor)
      rig = setup_otel_test_rig

      # Create Anthropic client and instrument it
      client = Anthropic::Client.new(api_key: get_anthropic_key)
      Braintrust.instrument!(:anthropic, target: client, tracer_provider: rig.tracer_provider)

      # Make a simple beta message request
      message = client.beta.messages.create(
        model: "claude-sonnet-4-20250514",
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

      # Verify span name (same as stable API)
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
      assert_equal "beta", metadata["api_version"], "Should have api_version: beta"
      assert_equal "claude-sonnet-4-20250514", metadata["model"]
      assert_equal 10, metadata["max_tokens"]

      # Verify braintrust.metrics contains token usage
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics["tokens"] > 0

      # Verify time_to_first_token is present and non-negative
      assert metrics.key?("time_to_first_token"), "Should have time_to_first_token metric"
      assert metrics["time_to_first_token"] >= 0, "time_to_first_token should be non-negative"
    end
  end

  def test_creates_span_with_betas_array
    VCR.use_cassette("anthropic/beta_with_betas_array") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and instrument it
      client = Anthropic::Client.new(api_key: get_anthropic_key)
      Braintrust.instrument!(:anthropic, target: client, tracer_provider: rig.tracer_provider)

      # Make a request with betas array
      message = client.beta.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 10,
        betas: ["structured-outputs-2025-11-13"],
        messages: [
          {role: "user", content: "Say 'test'"}
        ]
      )

      # Verify response
      refute_nil message

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "anthropic.messages.create", span.name

      # Verify metadata includes betas array
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "beta", metadata["api_version"]
      assert metadata["betas"], "Should capture betas array"
      assert_equal ["structured-outputs-2025-11-13"], metadata["betas"]
    end
  end

  def test_creates_span_with_structured_outputs
    # Structured outputs require specific models (Claude Sonnet 4.5, Opus 4.1/4.5, Haiku 4.5)
    # Skip on SDK versions or environments where these models aren't available
    skip_unless_structured_outputs_available!

    VCR.use_cassette("anthropic/beta_structured_outputs") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and instrument it
      client = Anthropic::Client.new(api_key: get_anthropic_key)
      Braintrust.instrument!(:anthropic, target: client, tracer_provider: rig.tracer_provider)

      # Make a request with structured outputs
      # Format: {type: "json_schema", schema: {...}}
      output_format = {
        type: "json_schema",
        schema: {
          type: "object",
          properties: {
            name: {type: "string"},
            age: {type: "integer"}
          },
          required: ["name", "age"],
          additionalProperties: false
        }
      }

      message = client.beta.messages.create(
        model: "claude-sonnet-4-5-20250514",
        max_tokens: 100,
        betas: ["structured-outputs-2025-11-13"],
        output_format: output_format,
        messages: [
          {role: "user", content: "Generate a random person with name and age"}
        ]
      )

      # Verify response
      refute_nil message

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "anthropic.messages.create", span.name

      # Verify metadata includes output_format
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "beta", metadata["api_version"]
      assert metadata["output_format"], "Should capture output_format"
      assert_equal "json_schema", metadata["output_format"]["type"]
    end
  end

  def test_handles_beta_streaming
    # Beta streaming requires SDK >= 1.16.0 due to SDK bug with BetaRawMessageStartEvent
    skip_unless_beta_streaming_available!

    VCR.use_cassette("anthropic/beta_streaming") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and instrument it
      client = Anthropic::Client.new(api_key: get_anthropic_key)
      Braintrust.instrument!(:anthropic, target: client, tracer_provider: rig.tracer_provider)

      # Make a streaming request via beta API
      stream = client.beta.messages.stream(
        model: "claude-sonnet-4-20250514",
        max_tokens: 50,
        messages: [
          {role: "user", content: "Count to 3"}
        ]
      )

      # Consume the stream
      stream.each do |event|
        # Just consume events
      end

      # Single span created during consumption
      span = rig.drain_one

      assert_equal "anthropic.messages.create", span.name

      # Verify input captured on span
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]

      # Verify metadata includes api_version: beta and stream flag
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "beta", metadata["api_version"]
      assert_equal true, metadata["stream"]
    end
  end

  def test_beta_and_stable_coexist
    VCR.use_cassette("anthropic/beta_and_stable_coexist") do
      # Set up test rig
      rig = setup_otel_test_rig

      # Create Anthropic client and instrument it
      client = Anthropic::Client.new(api_key: get_anthropic_key)
      Braintrust.instrument!(:anthropic, target: client, tracer_provider: rig.tracer_provider)

      # Make a stable API call
      stable_message = client.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 10,
        messages: [
          {role: "user", content: "Say 'stable'"}
        ]
      )

      # Make a beta API call
      beta_message = client.beta.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 10,
        messages: [
          {role: "user", content: "Say 'beta'"}
        ]
      )

      # Verify responses
      refute_nil stable_message
      refute_nil beta_message

      # Drain both spans
      spans = rig.drain
      assert_equal 2, spans.length, "Should have created 2 spans"

      stable_span = spans[0]
      beta_span = spans[1]

      # Both should have the same span name
      assert_equal "anthropic.messages.create", stable_span.name
      assert_equal "anthropic.messages.create", beta_span.name

      # Stable span should NOT have api_version: beta
      stable_metadata = JSON.parse(stable_span.attributes["braintrust.metadata"])
      refute_equal "beta", stable_metadata["api_version"]

      # Beta span SHOULD have api_version: beta
      beta_metadata = JSON.parse(beta_span.attributes["braintrust.metadata"])
      assert_equal "beta", beta_metadata["api_version"]
    end
  end

  private

  def skip_unless_beta_streaming_available!
    # Beta streaming requires SDK >= 1.16.0 due to SDK bug where
    # MessageStream.accumulate_event doesn't handle BetaRawMessageStartEvent
    spec = Gem.loaded_specs["anthropic"]
    if spec && spec.version < Gem::Version.new("1.16.0")
      skip "Beta streaming requires anthropic gem >= 1.16.0 (SDK bug in earlier versions)"
    end
  end

  def skip_unless_structured_outputs_available!
    # Structured outputs require specific models (Claude Sonnet 4.5, etc.)
    # that may not be available in all environments
    skip "Structured outputs test requires model availability (skipped for now)"
  end
end
