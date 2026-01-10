# frozen_string_literal: true

require "test_helper"
require_relative "../integration_helper"
require "braintrust/contrib/openai/instrumentation/chat"

class Braintrust::Contrib::OpenAI::Instrumentation::Chat::CompletionsTest < Minitest::Test
  Completions = Braintrust::Contrib::OpenAI::Instrumentation::Chat::Completions

  # --- .included ---

  def test_included_prepends_instance_methods
    base = Class.new
    mock = Minitest::Mock.new
    mock.expect(:include?, false, [Completions::InstanceMethods])
    mock.expect(:prepend, nil, [Completions::InstanceMethods])

    base.define_singleton_method(:ancestors) { mock }
    base.define_singleton_method(:prepend) { |mod| mock.prepend(mod) }

    Completions.included(base)

    mock.verify
  end

  def test_included_skips_prepend_when_already_applied
    base = Class.new do
      include Braintrust::Contrib::OpenAI::Instrumentation::Chat::Completions
    end

    # Should not raise or double-prepend
    Completions.included(base)

    # InstanceMethods should appear only once in ancestors
    count = base.ancestors.count { |a| a == Completions::InstanceMethods }
    assert_equal 1, count
  end

  # --- .applied? ---

  def test_applied_returns_false_when_not_included
    base = Class.new

    refute Completions.applied?(base)
  end

  def test_applied_returns_true_when_included
    base = Class.new do
      include Braintrust::Contrib::OpenAI::Instrumentation::Chat::Completions
    end

    assert Completions.applied?(base)
  end
end

# E2E tests for Chat::Completions instrumentation
class Braintrust::Contrib::OpenAI::Instrumentation::Chat::CompletionsE2ETest < Minitest::Test
  include Braintrust::Contrib::OpenAI::IntegrationHelper

  def setup
    skip_unless_openai!
  end

  # --- #create ---

  def test_create_creates_span_with_correct_attributes
    VCR.use_cassette("openai/chat_completions") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      response = client.chat.completions.create(
        messages: [
          {role: "system", content: "You are a test assistant."},
          {role: "user", content: "Say 'test'"}
        ],
        model: "gpt-4o-mini",
        max_tokens: 10,
        temperature: 0.5
      )

      refute_nil response
      refute_nil response.choices[0].message.content

      span = rig.drain_one

      assert_equal "Chat Completion", span.name

      # Verify input
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert_equal 2, input.length
      assert_equal "system", input[0]["role"]
      assert_equal "user", input[1]["role"]

      # Verify output
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert_equal 1, output.length
      assert_equal "assistant", output[0]["message"]["role"]

      # Verify metadata
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "openai", metadata["provider"]
      assert_equal "/v1/chat/completions", metadata["endpoint"]
      # Model is overwritten with response value (includes version suffix)
      assert_match(/\Agpt-4o-mini/, metadata["model"])

      # Verify metrics
      assert span.attributes.key?("braintrust.metrics")
      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics.key?("time_to_first_token")
    end
  end

  def test_create_parses_advanced_token_metrics
    VCR.use_cassette("openai/advanced_tokens") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      response = client.chat.completions.create(
        messages: [{role: "user", content: "test"}],
        model: "gpt-4o-mini",
        max_tokens: 10
      )

      refute_nil response

      span = rig.drain_one
      metrics = JSON.parse(span.attributes["braintrust.metrics"])

      # Basic metrics should always be present
      assert metrics["prompt_tokens"] > 0
      assert metrics["completion_tokens"] > 0
      assert metrics["tokens"] > 0

      # If the response includes token_details, verify they're parsed with correct naming
      # - prompt_tokens_details.cached_tokens → prompt_cached_tokens
      # - completion_tokens_details.reasoning_tokens → completion_reasoning_tokens
      if response.usage.respond_to?(:prompt_tokens_details) && response.usage.prompt_tokens_details
        details = response.usage.prompt_tokens_details
        if details.respond_to?(:cached_tokens) && details.cached_tokens
          assert metrics.key?("prompt_cached_tokens")
          assert_equal details.cached_tokens, metrics["prompt_cached_tokens"]
        end
      end

      if response.usage.respond_to?(:completion_tokens_details) && response.usage.completion_tokens_details
        details = response.usage.completion_tokens_details
        if details.respond_to?(:reasoning_tokens) && details.reasoning_tokens
          assert metrics.key?("completion_reasoning_tokens")
          assert_equal details.reasoning_tokens, metrics["completion_reasoning_tokens"]
        end
      end
    end
  end

  def test_create_handles_vision_messages
    VCR.use_cassette("openai/vision") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      response = client.chat.completions.create(
        messages: [
          {
            role: "user",
            content: [
              {type: "text", text: "What color is this image?"},
              {type: "image_url", image_url: {url: "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/320px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"}}
            ]
          }
        ],
        model: "gpt-4o-mini",
        max_tokens: 50
      )

      refute_nil response

      span = rig.drain_one
      input = JSON.parse(span.attributes["braintrust.input_json"])

      assert_instance_of Array, input[0]["content"]
      assert_equal "text", input[0]["content"][0]["type"]
      assert_equal "image_url", input[0]["content"][1]["type"]
    end
  end

  def test_create_handles_tool_messages
    VCR.use_cassette("openai/tool_messages") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)

      tools = [{
        type: "function",
        function: {
          name: "get_weather",
          description: "Get the current weather",
          parameters: {type: "object", properties: {location: {type: "string"}}, required: ["location"]}
        }
      }]

      first_response = client.chat.completions.create(
        messages: [{role: "user", content: "What's the weather in Paris?"}],
        model: "gpt-4o-mini",
        tools: tools,
        max_tokens: 100
      )

      tool_call = first_response.choices[0].message.tool_calls&.first
      skip "Model didn't call tool" unless tool_call

      client.chat.completions.create(
        messages: [
          {role: "user", content: "What's the weather in Paris?"},
          {role: "assistant", content: nil, tool_calls: [{id: tool_call.id, type: "function", function: {name: tool_call.function.name, arguments: tool_call.function.arguments}}]},
          {role: "tool", tool_call_id: tool_call.id, content: "Sunny, 22°C"}
        ],
        model: "gpt-4o-mini",
        tools: tools,
        max_tokens: 100
      )

      spans = rig.drain
      span = spans[1]
      input = JSON.parse(span.attributes["braintrust.input_json"])

      assert_equal "tool", input[2]["role"]
      assert_equal tool_call.id, input[2]["tool_call_id"]
    end
  end

  def test_create_records_exception_on_error
    VCR.use_cassette("openai/create_error") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)

      client = OpenAI::Client.new(api_key: "invalid_key")
      Braintrust.instrument!(:openai, target: client, tracer_provider: rig.tracer_provider)

      assert_raises do
        client.chat.completions.create(
          messages: [{role: "user", content: "test"}],
          model: "gpt-4o-mini"
        )
      end

      span = rig.drain_one
      assert_equal OpenTelemetry::Trace::Status::ERROR, span.status.code
      assert span.events.any? { |e| e.name == "exception" }
    end
  end

  # --- #stream_raw ---

  def test_stream_raw_aggregates_chunks
    VCR.use_cassette("openai/streaming") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      stream = client.chat.completions.stream_raw(
        messages: [{role: "user", content: "Count from 1 to 3"}],
        model: "gpt-4o-mini",
        max_tokens: 50,
        stream_options: {include_usage: true}
      )

      full_content = ""
      stream.each do |chunk|
        delta_content = chunk.choices[0]&.delta&.content
        full_content += delta_content if delta_content
      end

      refute_empty full_content

      # Single span created during consumption
      span = rig.drain_one

      assert_equal "Chat Completion", span.name

      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert output[0]["message"]["content"].length > 0

      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal true, metadata["stream"]

      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0
      assert metrics.key?("time_to_first_token")
    end
  end

  def test_stream_raw_handles_multiple_choices
    VCR.use_cassette("openai/streaming_multiple_choices") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      stream = client.chat.completions.stream_raw(
        messages: [{role: "user", content: "Say either 'hello' or 'hi' in one word"}],
        model: "gpt-4o-mini",
        max_tokens: 10,
        n: 2,
        stream_options: {include_usage: true}
      )

      stream.each { |chunk| } # consume all chunks

      # Single span created during consumption
      span = rig.drain_one

      assert_equal "Chat Completion", span.name

      output = JSON.parse(span.attributes["braintrust.output_json"])

      assert_equal 2, output.length, "Expected 2 choices in output"
      assert output[0]["message"]["content"].length > 0
      assert output[1]["message"]["content"].length > 0

      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal 2, metadata["n"]
    end
  end

  def test_stream_raw_closes_span_on_partial_consumption
    VCR.use_cassette("openai/partial_stream") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      stream = client.chat.completions.stream_raw(
        messages: [{role: "user", content: "Count from 1 to 10"}],
        model: "gpt-4o-mini",
        max_tokens: 50
      )

      chunk_count = 0
      begin
        stream.each do |chunk|
          chunk_count += 1
          break if chunk_count >= 2
        end
      rescue StopIteration
      end

      # Single span created during consumption
      span = rig.drain_one

      assert_equal "Chat Completion", span.name
      assert span.attributes.key?("braintrust.input_json")
    end
  end

  def test_stream_raw_records_exception_on_error
    VCR.use_cassette("openai/stream_error") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)

      client = OpenAI::Client.new(api_key: "invalid_key")
      Braintrust.instrument!(:openai, target: client, tracer_provider: rig.tracer_provider)

      assert_raises do
        stream = client.chat.completions.stream_raw(
          messages: [{role: "user", content: "test"}],
          model: "gpt-4o-mini"
        )
        stream.each { |chunk| }
      end

      # No span created when stream fails before consumption
      spans = rig.drain
      assert_empty spans, "No span should be created when stream fails before consumption"
    end
  end

  # --- #stream ---

  def test_stream_with_text_method
    VCR.use_cassette("openai/streaming_text") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      stream = client.chat.completions.stream(
        messages: [{role: "user", content: "Count from 1 to 3"}],
        model: "gpt-4o-mini",
        max_tokens: 50,
        stream_options: {include_usage: true}
      )

      full_text = ""
      stream.text.each { |delta| full_text += delta }

      refute_empty full_text

      # Single span created during consumption
      span = rig.drain_one

      assert_equal "Chat Completion", span.name

      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert output[0]["message"]["content"].length > 0
    end
  end

  def test_stream_with_get_final_completion
    VCR.use_cassette("openai/streaming_get_final_completion") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      stream = client.chat.completions.stream(
        messages: [{role: "user", content: "Say hello"}],
        model: "gpt-4o-mini",
        max_tokens: 20,
        stream_options: {include_usage: true}
      )

      completion = stream.get_final_completion

      refute_nil completion
      refute_nil completion.choices[0].message.content

      # Single span created during consumption
      span = rig.drain_one

      assert_equal "Chat Completion", span.name

      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert output[0]["message"]["content"]
    end
  end

  def test_stream_with_get_output_text
    VCR.use_cassette("openai/streaming_get_output_text") do
      rig = setup_otel_test_rig
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)
      Braintrust::Contrib::OpenAI::Integration.patch!

      client = OpenAI::Client.new(api_key: get_openai_key)
      stream = client.chat.completions.stream(
        messages: [{role: "user", content: "Say hello"}],
        model: "gpt-4o-mini",
        max_tokens: 20,
        stream_options: {include_usage: true}
      )

      output_text = stream.get_output_text

      refute_empty output_text

      # Single span created during consumption
      span = rig.drain_one

      assert_equal "Chat Completion", span.name

      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert output[0]["message"]["content"]
    end
  end
end
