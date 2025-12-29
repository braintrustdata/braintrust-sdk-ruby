# frozen_string_literal: true

require "test_helper"
require_relative "../integration_helper"
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
  include Braintrust::Contrib::RubyLLM::IntegrationHelper

  def setup
    skip_unless_ruby_llm!
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

      # Verify time_to_first_token is present and non-negative
      assert metrics.key?("time_to_first_token"), "Should have time_to_first_token metric"
      assert metrics["time_to_first_token"] >= 0, "time_to_first_token should be non-negative"
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

      # Verify metrics are present
      assert span.attributes.key?("braintrust.metrics"), "Should have metrics attribute"
      metrics = JSON.parse(span.attributes["braintrust.metrics"])

      # Verify time_to_first_token
      assert metrics.key?("time_to_first_token"), "Should have time_to_first_token metric"
      assert metrics["time_to_first_token"] >= 0, "time_to_first_token should be non-negative"

      # Verify token usage metrics
      assert metrics["prompt_tokens"] > 0, "Should have prompt_tokens > 0"
      assert metrics["completion_tokens"] > 0, "Should have completion_tokens > 0"
      assert metrics["tokens"] > 0, "Should have total tokens > 0"
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

  # --- Attachment handling (GitHub issue #71) ---

  # Test for GitHub issue #71: Content object not properly serialized
  # When a message has attachments, RubyLLM returns a Content object instead of a string
  # The SDK should include both text and attachments in the trace
  def test_format_message_for_input_handles_content_object_with_attachments
    skip "RubyLLM gem not available" unless defined?(::RubyLLM)

    with_tmp_file(data: "This is test content") do |tmpfile|
      # Create a Content object with an attachment (this triggers the Content object return)
      content = ::RubyLLM::Content.new("Hello, this is the actual text content")
      content.add_attachment(tmpfile.path)

      # Create a message with the Content object (simulates message with attachment)
      msg = ::RubyLLM::Message.new(role: :user, content: content)

      # Verify the precondition: msg.content returns a Content object, not a string
      assert msg.content.is_a?(::RubyLLM::Content),
        "Precondition failed: Expected Content object when message has attachments"

      # Create a minimal chat-like object to test the helper method
      chat_class = Class.new do
        include Braintrust::Contrib::RubyLLM::Instrumentation::Chat
      end
      chat = chat_class.new

      # Call the method under test
      result = chat.send(:format_message_for_input, msg)

      # When attachments are present, content should be a multipart array
      assert_equal "user", result["role"]
      assert result["content"].is_a?(Array), "Content should be an array when attachments are present"
      assert_equal 2, result["content"].length, "Content should have text and attachment parts"

      # Verify text part
      text_part = result["content"].find { |p| p["type"] == "text" }
      refute_nil text_part, "Should have a text part"
      assert_equal "Hello, this is the actual text content", text_part["text"]

      # Verify attachment part (OpenAI image_url format)
      attachment_part = result["content"].find { |p| p["type"] == "image_url" }
      refute_nil attachment_part, "Should have an attachment part"
      assert attachment_part["image_url"]["url"].start_with?("data:text/plain;base64,"),
        "Attachment should be a data URL with base64 encoded content"

      # Verify no object references
      refute result.to_s.include?("RubyLLM::Content"),
        "Result should not contain Content object reference"
    end
  end

  # Test for GitHub issue #71: Content object with image attachment
  # Verifies attachments are properly included in traces (similar to braintrust-go-sdk)
  def test_format_message_for_input_handles_image_attachment
    skip "RubyLLM gem not available" unless defined?(::RubyLLM)

    with_png_file do |tmpfile|
      # Create a Content object with an image attachment
      content = ::RubyLLM::Content.new("What's in this image?")
      content.add_attachment(tmpfile.path)

      # Create a message with the Content object
      msg = ::RubyLLM::Message.new(role: :user, content: content)

      # Verify the precondition: msg.content returns a Content object
      assert msg.content.is_a?(::RubyLLM::Content),
        "Precondition failed: Expected Content object when message has image attachment"
      assert_equal 1, msg.content.attachments.count,
        "Expected one attachment"

      # Create a minimal chat-like object to test the helper method
      chat_class = Class.new do
        include Braintrust::Contrib::RubyLLM::Instrumentation::Chat
      end
      chat = chat_class.new

      # Call the method under test
      result = chat.send(:format_message_for_input, msg)

      # Verify multipart content array is returned
      assert_equal "user", result["role"]
      assert result["content"].is_a?(Array), "Content should be an array when attachments are present"
      assert_equal 2, result["content"].length, "Content should have text and attachment parts"

      # Verify text part
      text_part = result["content"].find { |p| p["type"] == "text" }
      refute_nil text_part, "Should have a text part"
      assert_equal "What's in this image?", text_part["text"]

      # Verify attachment part (OpenAI image_url format)
      attachment_part = result["content"].find { |p| p["type"] == "image_url" }
      refute_nil attachment_part, "Should have an attachment part"
      assert attachment_part["image_url"]["url"].start_with?("data:image/png;base64,"),
        "Attachment should be a data URL with base64 encoded PNG"

      # Verify no object references in the result
      refute result.to_s.include?("RubyLLM::Content"),
        "Result should not contain Content object reference"
      refute result.to_s.include?("RubyLLM::Attachment"),
        "Result should not contain Attachment object reference"
    end
  end

  # Test for GitHub issue #71: build_input_messages works with Content objects
  # Verifies the full flow works end-to-end with attachments
  def test_build_input_messages_handles_content_objects_with_attachments
    skip "RubyLLM gem not available" unless defined?(::RubyLLM)

    with_png_file do |tmpfile|
      # Configure RubyLLM
      ::RubyLLM.configure do |config|
        config.openai_api_key = "test-key"
      end

      # Create a chat instance with a message containing an attachment
      chat = ::RubyLLM.chat(model: "gpt-4o-mini")

      # Add message with image attachment using RubyLLM's API
      content = ::RubyLLM::Content.new("Describe this image")
      content.add_attachment(tmpfile.path)
      chat.add_message(role: :user, content: content)

      # Instrument the chat to get access to the helper method
      Braintrust.instrument!(:ruby_llm, target: chat)

      # Call the method under test
      result = chat.send(:build_input_messages)

      # Verify the result
      assert_equal 1, result.length, "Expected one message"
      assert_equal "user", result[0]["role"]

      # Content should be an array with text and attachment parts
      content_parts = result[0]["content"]
      assert content_parts.is_a?(Array), "Content should be an array when attachments are present"
      assert_equal 2, content_parts.length, "Content should have text and attachment parts"

      # Verify text part
      text_part = content_parts.find { |p| p["type"] == "text" }
      refute_nil text_part, "Should have a text part"
      assert_equal "Describe this image", text_part["text"]

      # Verify attachment part (OpenAI image_url format)
      attachment_part = content_parts.find { |p| p["type"] == "image_url" }
      refute_nil attachment_part, "Should have an attachment part"
      assert attachment_part["image_url"]["url"].start_with?("data:image/png;base64,"),
        "Attachment should be a data URL with base64 encoded PNG"

      # Verify no object references
      refute result.to_s.include?("RubyLLM::Content"),
        "Result should not contain Content object reference"
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
