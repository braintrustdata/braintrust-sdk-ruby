# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/ruby_llm/instrumentation/chat"

class Braintrust::Contrib::RubyLLM::Instrumentation::ChatTest < Minitest::Test
  Chat = Braintrust::Contrib::RubyLLM::Instrumentation::Chat

  # --- .included ---

  def test_included_prepends_instance_methods
    base = Class.new
    mock = Minitest::Mock.new
    mock.expect(:include?, false, [Chat::InstanceMethods])
    mock.expect(:prepend, nil, [Chat::InstanceMethods])

    base.define_singleton_method(:ancestors) { mock }
    base.define_singleton_method(:prepend) { |mod| mock.prepend(mod) }

    Chat.included(base)

    mock.verify
  end

  def test_included_skips_prepend_when_already_applied
    base = Class.new do
      include Braintrust::Contrib::RubyLLM::Instrumentation::Chat
    end

    # Should not raise or double-prepend
    Chat.included(base)

    # InstanceMethods should appear only once in ancestors
    count = base.ancestors.count { |a| a == Chat::InstanceMethods }
    assert_equal 1, count
  end

  # --- .applied? ---

  def test_applied_returns_false_when_not_included
    base = Class.new

    refute Chat.applied?(base)
  end

  def test_applied_returns_true_when_included
    base = Class.new do
      include Braintrust::Contrib::RubyLLM::Instrumentation::Chat
    end

    assert Chat.applied?(base)
  end
end

# Define test tool classes for different ruby_llm versions
if defined?(RubyLLM)
  RUBY_LLM_VERSION = Gem.loaded_specs["ruby_llm"]&.version || Gem::Version.new("0.0.0")
  SUPPORTS_PARAMS_DSL = Gem::Version.new("1.9.0") <= RUBY_LLM_VERSION

  # Tool for ruby_llm 1.8+ (using param - singular)
  class WeatherTestTool < RubyLLM::Tool
    description "Get the current weather for a location"

    param :location, type: :string, desc: "The city and state, e.g. San Francisco, CA"
    param :unit, type: :string, desc: "Temperature unit (celsius or fahrenheit)"

    def execute(location:, unit: "fahrenheit")
      {location: location, temperature: 72, unit: unit, conditions: "sunny"}
    end
  end
end

# E2E tests for Chat instrumentation
class Braintrust::Contrib::RubyLLM::Instrumentation::ChatE2ETest < Minitest::Test
  def setup
    skip "RubyLLM gem not available" unless defined?(::RubyLLM)
  end

  # --- #complete (non-streaming) ---

  def test_complete_creates_span_with_correct_attributes
    VCR.use_cassette("contrib/ruby_llm/basic_chat") do
      rig = setup_otel_test_rig

      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      chat = RubyLLM.chat(model: "gpt-4o-mini")
      Braintrust.instrument!(:ruby_llm, target: chat, tracer_provider: rig.tracer_provider)

      response = chat.ask("Say 'test'")

      refute_nil response
      refute_nil response.content
      assert response.content.length > 0

      span = rig.drain_one

      assert_equal "ruby_llm.chat", span.name

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

  # --- #complete (streaming) ---

  def test_streaming_complete_creates_span
    VCR.use_cassette("contrib/ruby_llm/streaming_chat") do
      rig = setup_otel_test_rig

      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      chat = RubyLLM.chat(model: "gpt-4o-mini")
      Braintrust.instrument!(:ruby_llm, target: chat, tracer_provider: rig.tracer_provider)

      chunks = []
      chat.ask("Count to 3") do |chunk|
        chunks << chunk
      end

      refute_empty chunks

      span = rig.drain_one

      assert_equal "ruby_llm.chat", span.name

      # Verify input
      assert span.attributes.key?("braintrust.input_json")

      # Verify output was aggregated
      assert span.attributes.key?("braintrust.output_json")
      output = JSON.parse(span.attributes["braintrust.output_json"])
      refute_nil output

      # Verify metadata has stream flag
      assert span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "ruby_llm", metadata["provider"]
      assert_equal true, metadata["stream"]
    end
  end

  # --- Tool calling ---

  def test_tool_calling_creates_nested_spans
    skip "Tool calling test requires ruby_llm >= 1.9" unless defined?(SUPPORTS_PARAMS_DSL) && SUPPORTS_PARAMS_DSL

    VCR.use_cassette("contrib/ruby_llm/tool_calling") do
      rig = setup_otel_test_rig

      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      chat = RubyLLM.chat(model: "gpt-4o-mini")
      Braintrust.instrument!(:ruby_llm, target: chat, tracer_provider: rig.tracer_provider)
      chat.with_tool(WeatherTestTool)

      response = chat.ask("What's the weather like in San Francisco?")

      refute_nil response
      refute_nil response.content

      # Should have multiple spans: chat + tool + possibly another chat for follow-up
      spans = rig.drain
      assert spans.length >= 2, "Expected at least 2 spans for tool calling (chat + tool)"

      # Find the chat span and tool span
      chat_spans = spans.select { |s| s.name == "ruby_llm.chat" }
      tool_spans = spans.select { |s| s.name.start_with?("ruby_llm.tool.") }

      assert chat_spans.length >= 1, "Expected at least one ruby_llm.chat span"
      assert tool_spans.length >= 1, "Expected at least one ruby_llm.tool.* span"

      # Verify tool span has correct attributes
      tool_span = tool_spans.first
      assert tool_span.attributes.key?("braintrust.span_attributes"), "Tool span should have span_attributes"
      span_attrs = JSON.parse(tool_span.attributes["braintrust.span_attributes"])
      assert_equal "tool", span_attrs["type"]
      assert tool_span.attributes.key?("braintrust.input_json"), "Tool span should have input"
      assert tool_span.attributes.key?("braintrust.output_json"), "Tool span should have output"

      # Verify chat span metadata contains exact tool schema (OpenAI format)
      chat_span = chat_spans.first
      metadata = JSON.parse(chat_span.attributes["braintrust.metadata"])

      expected_tools = [
        {
          "type" => "function",
          "function" => {
            "name" => "weather_test",
            "description" => "Get the current weather for a location",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "location" => {
                  "type" => "string",
                  "description" => "The city and state, e.g. San Francisco, CA"
                },
                "unit" => {
                  "type" => "string",
                  "description" => "Temperature unit (celsius or fahrenheit)"
                }
              },
              "required" => ["location", "unit"]
            }
          }
        }
      ]
      assert_equal expected_tools, metadata["tools"]
    end
  end

  # --- Direct complete() ---

  def test_direct_complete_creates_span
    VCR.use_cassette("contrib/ruby_llm/direct_complete") do
      rig = setup_otel_test_rig

      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      chat = RubyLLM.chat(model: "gpt-4o-mini")
      Braintrust.instrument!(:ruby_llm, target: chat, tracer_provider: rig.tracer_provider)

      # Simulate ActiveRecord integration: add message directly, then call complete()
      chat.add_message(role: :user, content: "Say 'hello'")
      response = chat.complete

      refute_nil response
      refute_nil response.content
      assert response.content.length > 0

      span = rig.drain_one

      assert_equal "ruby_llm.chat", span.name

      # Verify braintrust.input_json contains the message we added
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert input.is_a?(Array)
      assert input.length > 0
      user_msg = input.find { |m| m["role"] == "user" }
      refute_nil user_msg
      assert_includes user_msg["content"], "hello"
    end
  end

  # --- Idempotency ---

  def test_wrapping_is_idempotent
    VCR.use_cassette("contrib/ruby_llm/basic_chat") do
      rig = setup_otel_test_rig

      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      chat = RubyLLM.chat(model: "gpt-4o-mini")

      # Wrap twice - should not cause issues
      Braintrust.instrument!(:ruby_llm, target: chat, tracer_provider: rig.tracer_provider)
      Braintrust.instrument!(:ruby_llm, target: chat, tracer_provider: rig.tracer_provider)

      response = chat.ask("Say 'test'")

      refute_nil response

      # Drain and verify - should only have ONE span (not double-wrapped)
      span = rig.drain_one

      assert_equal "ruby_llm.chat", span.name
    end
  end

  # --- Class-level instrumentation ---

  def test_class_level_instrumentation_traces_new_instances
    VCR.use_cassette("contrib/ruby_llm/basic_chat") do
      rig = setup_otel_test_rig

      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      # Set the default tracer provider for class-level instrumentation
      Braintrust::Contrib.init(tracer_provider: rig.tracer_provider)

      # Instrument at the class level (no target)
      Braintrust.instrument!(:ruby_llm)

      # Create a NEW chat instance AFTER class-level instrumentation
      # This instance should automatically be traced without explicit instrumentation
      chat = RubyLLM.chat(model: "gpt-4o-mini")

      # Make a request - should be traced automatically
      response = chat.ask("Say 'test'")

      refute_nil response
      refute_nil response.content

      # Verify span was created (proving class-level instrumentation works)
      span = rig.drain_one

      assert_equal "ruby_llm.chat", span.name
      assert span.attributes.key?("braintrust.input_json")
      assert span.attributes.key?("braintrust.output_json")
      assert span.attributes.key?("braintrust.metadata")

      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "ruby_llm", metadata["provider"]
      assert_equal "gpt-4o-mini", metadata["model"]
    end
  end

  # --- Frozen hash handling ---

  def test_format_tool_schema_handles_frozen_hash
    skip "RubyLLM gem not available" unless defined?(::RubyLLM)

    # Create a mock tool object with frozen params_schema
    mock_tool = Object.new
    def mock_tool.name
      "test_tool"
    end

    def mock_tool.description
      "A test tool"
    end

    def mock_tool.params_schema
      {
        "type" => "object",
        "properties" => {},
        "required" => [],
        "additionalProperties" => false,
        "strict" => true
      }.freeze
    end

    # Create a minimal chat-like object to test the helper method
    chat_class = Class.new do
      include Braintrust::Contrib::RubyLLM::Instrumentation::Chat
    end
    chat = chat_class.new

    # Test format_tool_schema (via send since it's private)
    result = chat.send(:format_tool_schema, mock_tool, nil)

    # Verify the result is returned (not raising FrozenError)
    refute_nil result
    assert_equal "function", result["type"]
    assert_equal "test_tool", result["function"]["name"]

    # Verify the parameters don't contain RubyLLM-specific fields
    params = result["function"]["parameters"]
    refute params.key?("strict"), "strict should be removed"
    refute params.key?("additionalProperties"), "additionalProperties should be removed"
  end
end
