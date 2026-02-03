# frozen_string_literal: true

require "test_helper"

class Braintrust::PromptTest < Minitest::Test
  def setup
    # Sample function data as returned by API
    @function_data = {
      "id" => "func-123",
      "name" => "Test Prompt",
      "slug" => "test-prompt",
      "project_id" => "proj-456",
      "prompt_data" => {
        "prompt" => {
          "type" => "chat",
          "messages" => [
            {"role" => "system", "content" => "You are a helpful assistant."},
            {"role" => "user", "content" => "Hello {{name}}, please help with {{task}}."}
          ]
        },
        "options" => {
          "model" => "claude-3-5-sonnet",
          "params" => {"temperature" => 0.7, "max_tokens" => 1000}
        }
      }
    }
  end

  def test_prompt_initialization
    prompt = Braintrust::Prompt.new(@function_data)

    assert_equal "func-123", prompt.id
    assert_equal "Test Prompt", prompt.name
    assert_equal "test-prompt", prompt.slug
    assert_equal "proj-456", prompt.project_id
  end

  def test_prompt_messages
    prompt = Braintrust::Prompt.new(@function_data)
    messages = prompt.messages

    assert_equal 2, messages.length
    assert_equal "system", messages[0]["role"]
    assert_equal "You are a helpful assistant.", messages[0]["content"]
    assert_equal "user", messages[1]["role"]
  end

  def test_prompt_model
    prompt = Braintrust::Prompt.new(@function_data)

    assert_equal "claude-3-5-sonnet", prompt.model
  end

  def test_prompt_options
    prompt = Braintrust::Prompt.new(@function_data)
    options = prompt.options

    assert_equal "claude-3-5-sonnet", options["model"]
    assert_equal 0.7, options["params"]["temperature"]
    assert_equal 1000, options["params"]["max_tokens"]
  end

  def test_prompt_raw_returns_prompt_definition
    prompt = Braintrust::Prompt.new(@function_data)
    raw = prompt.prompt

    assert_equal "chat", raw["type"]
    assert raw.key?("messages")
  end

  def test_build_substitutes_variables
    prompt = Braintrust::Prompt.new(@function_data)
    result = prompt.build(name: "Alice", task: "coding")

    assert_equal "claude-3-5-sonnet", result[:model]
    assert_equal 2, result[:messages].length
    assert_equal "You are a helpful assistant.", result[:messages][0][:content]
    assert_equal "Hello Alice, please help with coding.", result[:messages][1][:content]
  end

  def test_build_with_string_keys
    prompt = Braintrust::Prompt.new(@function_data)
    result = prompt.build("name" => "Bob", "task" => "writing")

    assert_equal "Hello Bob, please help with writing.", result[:messages][1][:content]
  end

  def test_build_includes_params
    prompt = Braintrust::Prompt.new(@function_data)
    result = prompt.build(name: "Alice", task: "coding")

    assert_equal 0.7, result[:temperature]
    assert_equal 1000, result[:max_tokens]
  end

  def test_build_with_defaults
    prompt = Braintrust::Prompt.new(@function_data, defaults: {name: "Default User"})
    result = prompt.build(task: "testing")

    assert_equal "Hello Default User, please help with testing.", result[:messages][1][:content]
  end

  def test_build_overrides_defaults
    prompt = Braintrust::Prompt.new(@function_data, defaults: {name: "Default User"})
    result = prompt.build(name: "Override User", task: "testing")

    assert_equal "Hello Override User, please help with testing.", result[:messages][1][:content]
  end

  def test_build_strict_raises_on_missing_variable
    prompt = Braintrust::Prompt.new(@function_data)

    error = assert_raises(Braintrust::Error) do
      prompt.build({name: "Alice"}, strict: true)
    end

    assert_match(/missing.*task/i, error.message)
  end

  def test_build_non_strict_replaces_missing_variables_with_empty
    # Mustache standard behavior: missing variables become empty strings
    prompt = Braintrust::Prompt.new(@function_data)
    result = prompt.build(name: "Alice")

    assert_equal "Hello Alice, please help with .", result[:messages][1][:content]
  end

  def test_build_handles_nested_variables
    data = @function_data.dup
    data["prompt_data"]["prompt"]["messages"] = [
      {"role" => "user", "content" => "User: {{user.name}}, Email: {{user.email}}"}
    ]
    prompt = Braintrust::Prompt.new(data)

    result = prompt.build(user: {name: "Alice", email: "alice@example.com"})

    assert_equal "User: Alice, Email: alice@example.com", result[:messages][0][:content]
  end

  def test_build_does_not_escape_html_characters
    # LLM prompts should NOT have HTML escaping applied.
    # Standard Mustache would turn < into &lt; but we disable this.
    data = @function_data.dup
    data["prompt_data"]["prompt"]["messages"] = [
      {"role" => "user", "content" => "Write code: {{code}}"}
    ]
    prompt = Braintrust::Prompt.new(data)

    # These characters would be escaped by standard Mustache
    code_with_html = '<script>alert("test")</script> & other < > stuff'
    result = prompt.build(code: code_with_html)

    # Verify NO escaping occurred - raw characters preserved
    assert_equal "Write code: #{code_with_html}", result[:messages][0][:content]
    assert_includes result[:messages][0][:content], "<script>"
    assert_includes result[:messages][0][:content], '"test"'
    assert_includes result[:messages][0][:content], " & "
  end

  def test_build_preserves_ampersands_and_quotes
    # Ampersands and quotes are commonly escaped by HTML escapers
    data = @function_data.dup
    data["prompt_data"]["prompt"]["messages"] = [
      {"role" => "user", "content" => "Search for: {{query}}"}
    ]
    prompt = Braintrust::Prompt.new(data)

    result = prompt.build(query: 'foo & bar "baz"')

    # Should be raw, not &amp; or &quot;
    assert_equal 'Search for: foo & bar "baz"', result[:messages][0][:content]
  end

  # Template format tests

  def test_template_format_defaults_to_mustache
    prompt = Braintrust::Prompt.new(@function_data)

    assert_equal "mustache", prompt.template_format
  end

  def test_template_format_explicit_mustache
    data = @function_data.dup
    data["prompt_data"]["template_format"] = "mustache"
    prompt = Braintrust::Prompt.new(data)

    assert_equal "mustache", prompt.template_format

    # Should render mustache templates
    result = prompt.build(name: "Alice", task: "coding")
    assert_equal "Hello Alice, please help with coding.", result[:messages][1][:content]
  end

  def test_template_format_none_returns_unchanged
    data = @function_data.dup
    data["prompt_data"]["template_format"] = "none"
    data["prompt_data"]["prompt"]["messages"] = [
      {"role" => "user", "content" => "Literal {{braces}} should stay as-is"}
    ]
    prompt = Braintrust::Prompt.new(data)

    assert_equal "none", prompt.template_format

    # Should NOT render - return template unchanged
    result = prompt.build(braces: "REPLACED")
    assert_equal "Literal {{braces}} should stay as-is", result[:messages][0][:content]
  end

  def test_template_format_nunjucks_raises_error
    data = @function_data.dup
    data["prompt_data"]["template_format"] = "nunjucks"
    data["prompt_data"]["prompt"]["messages"] = [
      {"role" => "user", "content" => "{% if name %}Hello {{name}}{% endif %}"}
    ]
    prompt = Braintrust::Prompt.new(data)

    assert_equal "nunjucks", prompt.template_format

    error = assert_raises(Braintrust::Error) do
      prompt.build(name: "Alice")
    end

    assert_match(/nunjucks/i, error.message)
    assert_match(/not supported/i, error.message)
    assert_match(/ruby sdk/i, error.message)
  end

  def test_template_format_unknown_raises_error
    data = @function_data.dup
    data["prompt_data"]["template_format"] = "jinja2"
    prompt = Braintrust::Prompt.new(data)

    error = assert_raises(Braintrust::Error) do
      prompt.build(name: "Alice", task: "coding")
    end

    assert_match(/unknown template format/i, error.message)
    assert_match(/jinja2/i, error.message)
  end

  # Tools tests - basic behavior without schema assumptions

  def test_tools_returns_nil_when_not_defined
    prompt = Braintrust::Prompt.new(@function_data)
    assert_nil prompt.tools
  end

  def test_tools_returns_nil_for_empty_string
    data = @function_data.dup
    data["prompt_data"]["prompt"]["tools"] = ""
    prompt = Braintrust::Prompt.new(data)

    assert_nil prompt.tools
  end

  def test_tools_returns_nil_for_invalid_json
    data = @function_data.dup
    data["prompt_data"]["prompt"]["tools"] = "not valid json"
    prompt = Braintrust::Prompt.new(data)

    assert_nil prompt.tools
  end

  def test_build_excludes_tools_when_not_defined
    prompt = Braintrust::Prompt.new(@function_data)
    result = prompt.build(name: "Alice", task: "coding")

    refute result.key?(:tools)
  end
end

class Braintrust::PromptLoadTest < Minitest::Test
  def setup
    flunk "BRAINTRUST_API_KEY not set" unless ENV["BRAINTRUST_API_KEY"]
    @project_name = "ruby-sdk-test"
  end

  def test_prompt_load
    VCR.use_cassette("prompt/load") do
      Braintrust.init(blocking_login: true)

      # Create a prompt first
      api = Braintrust::API.new
      slug = "test-prompt-load"

      api.functions.create(
        project_name: @project_name,
        slug: slug,
        function_data: {type: "prompt"},
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "Say hello to {{name}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini"
          }
        }
      )

      # Load the prompt using Prompt.load
      prompt = Braintrust::Prompt.load(project: @project_name, slug: slug)

      assert_instance_of Braintrust::Prompt, prompt
      assert_equal slug, prompt.slug
      assert_equal "gpt-4o-mini", prompt.model
      assert_equal 1, prompt.messages.length

      # Test build
      result = prompt.build(name: "World")
      assert_equal "Say hello to World", result[:messages][0][:content]

      # Clean up
      api.functions.delete(id: prompt.id)
    ensure
      OpenTelemetry.tracer_provider.shutdown
    end
  end

  def test_prompt_load_not_found
    VCR.use_cassette("prompt/load_not_found") do
      Braintrust.init(blocking_login: true)

      error = assert_raises(Braintrust::Error) do
        Braintrust::Prompt.load(project: @project_name, slug: "nonexistent-prompt-xyz")
      end

      assert_match(/not found/i, error.message)
    ensure
      OpenTelemetry.tracer_provider.shutdown
    end
  end

  def test_prompt_load_with_version
    VCR.use_cassette("prompt/load_with_version") do
      Braintrust.init(blocking_login: true)

      api = Braintrust::API.new
      slug = "test-prompt-version"

      # Create a prompt and capture its version (_xact_id)
      created = api.functions.create(
        project_name: @project_name,
        slug: slug,
        function_data: {type: "prompt"},
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "Version test: {{name}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini"
          }
        }
      )

      version_id = created["_xact_id"]
      assert version_id, "Expected _xact_id in response"

      # Load the prompt with explicit version
      prompt = Braintrust::Prompt.load(
        project: @project_name,
        slug: slug,
        version: version_id
      )

      assert_instance_of Braintrust::Prompt, prompt
      assert_equal slug, prompt.slug
      assert_equal "gpt-4o-mini", prompt.model

      # Build and verify content
      result = prompt.build(name: "World")
      assert_equal "Version test: World", result[:messages][0][:content]

      # Clean up
      api.functions.delete(id: prompt.id)
    ensure
      OpenTelemetry.tracer_provider.shutdown
    end
  end

  def test_prompt_load_with_tools
    VCR.use_cassette("prompt/load_with_tools") do
      Braintrust.init(blocking_login: true)

      api = Braintrust::API.new
      slug = "test-prompt-tools"

      # Tools in OpenAI format - stored as JSON string per API schema
      tools = [
        {
          type: "function",
          function: {
            name: "get_weather",
            description: "Get the current weather in a location",
            parameters: {
              type: "object",
              properties: {
                location: {type: "string", description: "City name"}
              },
              required: ["location"]
            }
          }
        }
      ]

      # Create a prompt with tools
      api.functions.create(
        project_name: @project_name,
        slug: slug,
        function_data: {type: "prompt"},
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "What is the weather in {{city}}?"}
            ],
            tools: JSON.dump(tools)
          },
          options: {model: "gpt-4o-mini"}
        }
      )

      # Load the prompt
      prompt = Braintrust::Prompt.load(project: @project_name, slug: slug)

      # Verify tools accessor
      assert_instance_of Array, prompt.tools
      assert_equal 1, prompt.tools.length
      assert_equal "get_weather", prompt.tools[0]["function"]["name"]

      # Build and verify tools are included
      result = prompt.build(city: "Seattle")
      assert result.key?(:tools), "Expected build result to include :tools"
      assert_equal prompt.tools, result[:tools]
      assert_equal "What is the weather in Seattle?", result[:messages][0][:content]

      # Clean up
      api.functions.delete(id: prompt.id)
    ensure
      OpenTelemetry.tracer_provider.shutdown
    end
  end
end
