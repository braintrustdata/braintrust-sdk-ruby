# frozen_string_literal: true

require "test_helper"

# Explicitly load the patcher (lazy-loaded by integration)
require "braintrust/contrib/openai/patcher"

# Cross-cutting tests that verify chat and responses instrumentation work together
class Braintrust::Contrib::OpenAI::InstrumentationTest < Minitest::Test
  def setup
    if Gem.loaded_specs["ruby-openai"]
      skip "openai gem not available (found ruby-openai gem instead)"
    elsif !Gem.loaded_specs["openai"]
      skip "openai gem not available"
    end

    require "openai" unless defined?(OpenAI)
  end

  # --- Instance-level instrumentation ---

  def test_instance_instrumentation_only_patches_target_client
    # Skip if class-level patching already occurred from another test
    skip "class already patched by another test" if Braintrust::Contrib::OpenAI::ChatPatcher.patched?

    rig = setup_otel_test_rig

    # Create two clients BEFORE any patching
    client_traced = OpenAI::Client.new(api_key: "test-key")
    client_untraced = OpenAI::Client.new(api_key: "test-key")

    # Verify neither client is patched initially
    refute Braintrust::Contrib::OpenAI::ChatPatcher.patched?(target: client_traced),
      "client_traced should not be patched initially"
    refute Braintrust::Contrib::OpenAI::ChatPatcher.patched?(target: client_untraced),
      "client_untraced should not be patched initially"

    # Verify class is not patched
    refute Braintrust::Contrib::OpenAI::ChatPatcher.patched?,
      "class should not be patched initially"

    # Instrument only one client (instance-level)
    Braintrust.instrument!(:openai, target: client_traced, tracer_provider: rig.tracer_provider)

    # Only the traced client should be patched
    assert Braintrust::Contrib::OpenAI::ChatPatcher.patched?(target: client_traced),
      "client_traced should be patched after instrument!"
    refute Braintrust::Contrib::OpenAI::ChatPatcher.patched?(target: client_untraced),
      "client_untraced should NOT be patched after instrument!"

    # Class itself should NOT be patched (only the instance)
    refute Braintrust::Contrib::OpenAI::ChatPatcher.patched?,
      "class should NOT be patched when using instance-level instrumentation"
  end

  # --- Chat and Responses cross-cutting tests ---

  def test_chat_and_responses_do_not_interfere
    skip "Responses API not available" unless OpenAI::Client.instance_methods.include?(:responses)
    VCR.use_cassette("openai_chat_and_responses_no_interference") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)

      client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust.instrument!(:openai, target: client, tracer_provider: rig.tracer_provider)

      # Make a chat completion request
      chat_response = client.chat.completions.create(
        messages: [{role: "user", content: "Say hello"}],
        model: "gpt-4o-mini",
        max_tokens: 10
      )
      refute_nil chat_response

      # Make a responses API request
      responses_response = client.responses.create(
        model: "gpt-4o-mini",
        instructions: "You are a helpful assistant.",
        input: "Say goodbye"
      )
      refute_nil responses_response
      refute_nil responses_response.output

      # Verify both spans are correct
      spans = rig.drain
      assert_equal 2, spans.length

      chat_span = spans[0]
      assert_equal "Chat Completion", chat_span.name
      chat_metadata = JSON.parse(chat_span.attributes["braintrust.metadata"])
      assert_equal "/v1/chat/completions", chat_metadata["endpoint"]

      chat_input = JSON.parse(chat_span.attributes["braintrust.input_json"])
      assert_instance_of Array, chat_input
      assert_equal "user", chat_input[0]["role"]

      responses_span = spans[1]
      assert_equal "openai.responses.create", responses_span.name
      responses_metadata = JSON.parse(responses_span.attributes["braintrust.metadata"])
      assert_equal "/v1/responses", responses_metadata["endpoint"]

      responses_input = JSON.parse(responses_span.attributes["braintrust.input_json"])
      assert_equal "Say goodbye", responses_input
    end
  end

  def test_streaming_chat_and_responses_do_not_interfere
    VCR.use_cassette("openai_streaming_chat_and_responses_no_interference") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)

      client = OpenAI::Client.new(api_key: get_openai_key)
      Braintrust.instrument!(:openai, target: client, tracer_provider: rig.tracer_provider)

      # Make a streaming chat completion request
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

      # Make a streaming responses API request
      responses_event_count = 0
      responses_stream = client.responses.stream(
        model: "gpt-4o-mini",
        instructions: "You are a helpful assistant.",
        input: "Say hello"
      )
      responses_stream.each { |event| responses_event_count += 1 }
      assert responses_event_count > 0

      # Verify spans are correct (1 per streaming operation: created during consumption)
      spans = rig.drain
      assert_equal 2, spans.length

      # Chat streaming: single span created during consumption
      chat_span = spans.find { |s| s.name == "Chat Completion" }
      assert chat_span, "Expected chat span"

      chat_metadata = JSON.parse(chat_span.attributes["braintrust.metadata"])
      assert_equal true, chat_metadata["stream"]

      chat_output = JSON.parse(chat_span.attributes["braintrust.output_json"])
      assert chat_output[0]["message"]["content"].length > 0

      # Responses streaming: single span created during consumption
      responses_span = spans.find { |s| s.name == "openai.responses.create" }
      assert responses_span, "Expected responses span"

      responses_metadata = JSON.parse(responses_span.attributes["braintrust.metadata"])
      assert_equal true, responses_metadata["stream"]
    end
  end
end
