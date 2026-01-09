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

  def test_build_non_strict_leaves_missing_variables
    prompt = Braintrust::Prompt.new(@function_data)
    result = prompt.build(name: "Alice")

    assert_equal "Hello Alice, please help with {{task}}.", result[:messages][1][:content]
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
end
