# frozen_string_literal: true

require "test_helper"

# Define test tool classes for different ruby_llm versions
# Must be defined at module level for RubyLLM to find them properly
if defined?(RubyLLM)
  # Check ruby_llm version to determine which API to use
  RUBY_LLM_VERSION = Gem.loaded_specs["ruby_llm"]&.version || Gem::Version.new("0.0.0")
  SUPPORTS_PARAMS_DSL = Gem::Version.new("1.9.0") <= RUBY_LLM_VERSION

  # Tool for ruby_llm 1.8 (using param - singular)
  # This syntax works in 1.8+ including 1.9+ for backward compatibility
  class WeatherTestToolV18 < RubyLLM::Tool
    description "Get the current weather for a location"

    param :location, type: :string, desc: "The city and state, e.g. San Francisco, CA"
    param :unit, type: :string, desc: "Temperature unit (celsius or fahrenheit)"

    def execute(location:, unit: "fahrenheit")
      {location: location, temperature: 72, unit: unit, conditions: "sunny"}
    end
  end

  # Tool for ruby_llm 1.9+ (using params - plural)
  # This new DSL only works in 1.9+
  if SUPPORTS_PARAMS_DSL
    class WeatherTestToolV19 < RubyLLM::Tool
      description "Get the current weather for a location"

      params do
        string :location, description: "The city and state, e.g. San Francisco, CA"
        string :unit, description: "Temperature unit (celsius or fahrenheit)"
      end

      def execute(location:, unit: "fahrenheit")
        {location: location, temperature: 72, unit: unit, conditions: "sunny"}
      end
    end
  end
end

class RubyLLMIntegrationTest < Minitest::Test
  def setup
    # Skip all RubyLLM tests if the gem is not available
    skip "RubyLLM gem not available" unless defined?(RubyLLM)
  end

  def test_wrap_creates_span_for_basic_chat
    VCR.use_cassette("ruby_llm/basic_chat") do
      require "ruby_llm"

      # Set up test rig (includes Braintrust processor)
      rig = setup_otel_test_rig

      # Configure RubyLLM (use real key for recording, fake key for playback)
      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      # Create chat instance and wrap it with Braintrust tracing
      chat = RubyLLM.chat(model: "gpt-4o-mini")
      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)

      # Make a simple chat request
      response = chat.ask("Say 'test'")

      # Verify response
      refute_nil response
      refute_nil response.content
      assert response.content.length > 0

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
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

  def test_wrap_creates_span_for_streaming_chat
    VCR.use_cassette("ruby_llm/streaming_chat") do
      require "ruby_llm"

      # Set up test rig
      rig = setup_otel_test_rig

      # Configure RubyLLM (use real key for recording, fake key for playback)
      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      # Create chat instance and wrap it
      chat = RubyLLM.chat(model: "gpt-4o-mini")
      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)

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
      assert_equal "ruby_llm.chat", span.name

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

  def test_wrap_creates_span_for_tool_calling
    skip "Tool calling test requires ruby_llm >= 1.9" unless Gem::Version.new("1.9.0") <= RUBY_LLM_VERSION

    VCR.use_cassette("ruby_llm/tool_calling") do
      require "ruby_llm"

      # Set up test rig
      rig = setup_otel_test_rig

      # Configure RubyLLM
      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      # Create chat instance and wrap it
      chat = RubyLLM.chat(model: "gpt-4o-mini")
      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)
      chat.with_tool(WeatherTestToolV19)

      # Make a chat request that should trigger tool usage
      response = chat.ask("What's the weather like in San Francisco?")

      # Verify response
      refute_nil response
      refute_nil response.content

      # Tool calling creates sibling spans:
      # 1. ruby_llm.chat - the LLM conversation span
      # 2. ruby_llm.tool.* - tool execution span(s)
      spans = rig.drain
      assert spans.length >= 2, "Expected at least 2 spans for tool calling (chat + tool)"

      # Find the chat span and tool span
      chat_span = spans.find { |s| s.name == "ruby_llm.chat" }
      tool_span = spans.find { |s| s.name.start_with?("ruby_llm.tool.") }

      refute_nil chat_span, "Expected a ruby_llm.chat span"
      refute_nil tool_span, "Expected a ruby_llm.tool.* span"

      # Verify chat span has metadata with tools
      assert chat_span.attributes.key?("braintrust.metadata")
      metadata = JSON.parse(chat_span.attributes["braintrust.metadata"])
      assert_equal "ruby_llm", metadata["provider"]

      # Assert exact tool schema (OpenAI format with RubyLLM-specific fields stripped)
      expected_tools = [
        {
          "type" => "function",
          "function" => {
            "name" => "weather_test_tool_v19",
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

      # Verify chat span has output
      assert chat_span.attributes.key?("braintrust.output_json")
      output = JSON.parse(chat_span.attributes["braintrust.output_json"])
      refute_nil output

      # Verify tool span has correct attributes
      assert tool_span.attributes.key?("braintrust.span_attributes"), "Tool span should have span_attributes"
      span_attrs = JSON.parse(tool_span.attributes["braintrust.span_attributes"])
      assert_equal "tool", span_attrs["type"]
      assert tool_span.attributes.key?("braintrust.input_json"), "Tool span should have input"
      assert tool_span.attributes.key?("braintrust.output_json"), "Tool span should have output"
    end
  end

  # Test for GitHub issue #39: ActiveRecord integration calls complete() directly
  # This simulates how acts_as_chat uses RubyLLM - it adds messages to chat history
  # and then calls complete() directly, bypassing ask()
  def test_wrap_creates_span_for_direct_complete
    VCR.use_cassette("ruby_llm/direct_complete") do
      require "ruby_llm"

      # Set up test rig
      rig = setup_otel_test_rig

      # Configure RubyLLM
      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      # Create chat instance and wrap it
      chat = RubyLLM.chat(model: "gpt-4o-mini")
      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)

      # Simulate ActiveRecord integration: add message directly, then call complete()
      chat.add_message(role: :user, content: "Say 'hello'")
      response = chat.complete

      # Verify response
      refute_nil response
      refute_nil response.content
      assert response.content.length > 0

      # Drain and verify span
      span = rig.drain_one

      # Verify span name
      assert_equal "ruby_llm.chat", span.name

      # Verify braintrust.input_json contains the message we added
      assert span.attributes.key?("braintrust.input_json")
      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert input.is_a?(Array)
      assert input.length > 0
      # The user message should be in the input
      user_msg = input.find { |m| m["role"] == "user" }
      refute_nil user_msg
      assert_includes user_msg["content"], "hello"

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

  def test_wrap_is_idempotent
    VCR.use_cassette("ruby_llm/basic_chat") do
      require "ruby_llm"

      # Set up test rig
      rig = setup_otel_test_rig

      # Configure RubyLLM
      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      # Create chat instance
      chat = RubyLLM.chat(model: "gpt-4o-mini")

      # Wrap it twice - should not cause issues
      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)
      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(chat, tracer_provider: rig.tracer_provider)

      # Make a chat request
      response = chat.ask("Say 'test'")

      # Verify response
      refute_nil response

      # Drain and verify - should only have ONE span (not double-wrapped)
      span = rig.drain_one

      # Verify span name
      assert_equal "ruby_llm.chat", span.name

      # Verify the wrapped flag is set
      assert chat.instance_variable_get(:@braintrust_wrapped)
    end
  end

  def test_wrap_module_creates_spans_for_all_instances
    VCR.use_cassette("ruby_llm/basic_chat") do
      require "ruby_llm"

      # Set up test rig
      rig = setup_otel_test_rig

      # Configure RubyLLM
      RubyLLM.configure do |config|
        config.openai_api_key = get_openai_key
      end

      # Wrap the module (not an instance)
      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap(tracer_provider: rig.tracer_provider)

      # Verify the wrapper module is stored
      assert ::RubyLLM::Chat.instance_variable_defined?(:@braintrust_wrapper_module)

      # Create multiple chat instances AFTER wrapping - they should all be traced
      chat1 = RubyLLM.chat(model: "gpt-4o-mini")
      chat2 = RubyLLM.chat(model: "gpt-4o-mini")
      chat3 = RubyLLM.chat(model: "gpt-4o-mini")

      # Make chat requests with each instance
      response1 = chat1.ask("Say 'test'")
      response2 = chat2.ask("Say 'test'")
      response3 = chat3.ask("Say 'test'")

      # Verify responses
      refute_nil response1
      refute_nil response2
      refute_nil response3

      # Drain and verify we got 3 spans (one per request)
      spans = rig.drain
      assert_equal 3, spans.length, "Expected 3 spans (one per request)"

      # Verify all spans have the correct name and attributes
      spans.each do |span|
        assert_equal "ruby_llm.chat", span.name
        assert span.attributes.key?("braintrust.input_json")
        assert span.attributes.key?("braintrust.output_json")
        assert span.attributes.key?("braintrust.metadata")
        assert span.attributes.key?("braintrust.metrics")
      end

      # Verify exporter is empty after drain
      assert_equal 0, rig.drain.length, "Exporter should be empty after drain"

      # Now unwrap the module
      Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.unwrap

      # Verify the wrapper module reference is removed
      refute ::RubyLLM::Chat.instance_variable_defined?(:@braintrust_wrapper_module)

      # Create new chat instances AFTER unwrapping - they should NOT be traced
      chat4 = RubyLLM.chat(model: "gpt-4o-mini")
      chat5 = RubyLLM.chat(model: "gpt-4o-mini")

      # Verify they are NOT wrapped
      refute chat4.instance_variable_defined?(:@braintrust_wrapped), "chat4 should not be wrapped"
      refute chat5.instance_variable_defined?(:@braintrust_wrapped), "chat5 should not be wrapped"

      # Make chat requests with the unwrapped instances
      response4 = chat4.ask("Say 'test'")
      response5 = chat5.ask("Say 'test'")

      # Verify responses still work (RubyLLM still functions)
      refute_nil response4
      refute_nil response5

      # Verify NO new spans were created (unwrap disabled tracing)
      spans_after_unwrap = rig.drain
      assert_equal 0, spans_after_unwrap.length, "Expected 0 spans after unwrap"
    end
  end

  # Test for frozen Hash bug in format_tool_schema
  # This reproduces the issue where tool_params from provider's tool_for method
  # returns a frozen hash, causing FrozenError when trying to delete keys
  def test_format_tool_schema_handles_frozen_hash
    # Create a mock tool object
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

    def mock_tool.respond_to?(method)
      [:name, :description, :params_schema].include?(method)
    end

    # Test with basic tool schema (no provider)
    # This will use build_basic_tool_schema which creates a tool schema
    # with the frozen params_schema from the tool
    result = Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.format_tool_schema(mock_tool, nil)

    # Verify the result is returned (not raising FrozenError)
    refute_nil result
    assert_equal "function", result["type"]
    assert_equal "test_tool", result["function"]["name"]
    assert_equal "A test tool", result["function"]["description"]

    # Verify the parameters don't contain RubyLLM-specific fields
    params = result["function"]["parameters"]
    refute params.key?("strict"), "strict should be removed"
    refute params.key?(:strict), "strict (symbol) should be removed"
    refute params.key?("additionalProperties"), "additionalProperties should be removed"
    refute params.key?(:additionalProperties), "additionalProperties (symbol) should be removed"

    # Verify the expected fields are still present
    assert_equal "object", params["type"]
    assert_equal({}, params["properties"])
    assert_equal [], params["required"]
  end

  # Test for GitHub issue #71: Content object not properly serialized
  # When a message has attachments, RubyLLM returns a Content object instead of a string
  # The SDK should include both text and attachments in the trace
  def test_format_message_for_input_handles_content_object_with_attachments
    with_tmp_file(data: "This is test content") do |tmpfile|
      # Create a Content object with an attachment (this triggers the Content object return)
      content = ::RubyLLM::Content.new("Hello, this is the actual text content")
      content.add_attachment(tmpfile.path)

      # Create a message with the Content object (simulates message with attachment)
      msg = ::RubyLLM::Message.new(role: :user, content: content)

      # Verify the precondition: msg.content returns a Content object, not a string
      assert msg.content.is_a?(::RubyLLM::Content),
        "Precondition failed: Expected Content object when message has attachments"

      # Call the method under test
      result = Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.format_message_for_input(msg)

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

      # Call the method under test
      result = Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.format_message_for_input(msg)

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

      # Call the method under test
      result = Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.build_input_messages(chat, nil)

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
end
