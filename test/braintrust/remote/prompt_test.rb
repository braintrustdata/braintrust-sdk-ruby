# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::PromptTest < Minitest::Test
  # ============================================
  # Constructor tests
  # ============================================

  def test_initializes_with_messages
    prompt = Braintrust::Remote::Prompt.new(
      messages: [{"role" => "user", "content" => "Hello"}]
    )

    assert_equal [{"role" => "user", "content" => "Hello"}], prompt.messages
    assert_nil prompt.model
  end

  def test_initializes_with_model
    prompt = Braintrust::Remote::Prompt.new(
      messages: [],
      model: "gpt-4"
    )

    assert_equal "gpt-4", prompt.model
  end

  def test_initializes_with_additional_params
    prompt = Braintrust::Remote::Prompt.new(
      messages: [],
      model: "gpt-4",
      temperature: 0.7,
      max_tokens: 100
    )

    assert_equal 0.7, prompt.params[:temperature]
    assert_equal 100, prompt.params[:max_tokens]
  end

  # ============================================
  # from_hash tests
  # ============================================

  def test_from_hash_creates_prompt_from_hash
    hash = {
      "messages" => [{"role" => "user", "content" => "Hello"}],
      "model" => "gpt-4"
    }

    prompt = Braintrust::Remote::Prompt.from_hash(hash)

    assert_instance_of Braintrust::Remote::Prompt, prompt
    assert_equal [{"role" => "user", "content" => "Hello"}], prompt.messages
    assert_equal "gpt-4", prompt.model
  end

  def test_from_hash_extracts_additional_params
    hash = {
      "messages" => [],
      "model" => "gpt-4",
      "temperature" => 0.9,
      "max_tokens" => 500
    }

    prompt = Braintrust::Remote::Prompt.from_hash(hash)

    assert_equal 0.9, prompt.params[:temperature]
    assert_equal 500, prompt.params[:max_tokens]
  end

  def test_from_hash_handles_symbol_keys
    hash = {
      messages: [{"role" => "user", "content" => "Hello"}],
      model: "gpt-4"
    }

    prompt = Braintrust::Remote::Prompt.from_hash(hash)

    assert_equal [{"role" => "user", "content" => "Hello"}], prompt.messages
    assert_equal "gpt-4", prompt.model
  end

  def test_from_hash_returns_prompt_if_already_prompt
    original = Braintrust::Remote::Prompt.new(
      messages: [{"role" => "user", "content" => "Hello"}],
      model: "gpt-4"
    )

    result = Braintrust::Remote::Prompt.from_hash(original)

    assert_same original, result
  end

  # ============================================
  # to_h tests
  # ============================================

  def test_to_h_returns_hash_representation
    prompt = Braintrust::Remote::Prompt.new(
      messages: [{"role" => "user", "content" => "Hello"}],
      model: "gpt-4"
    )

    result = prompt.to_h

    assert_equal [{"role" => "user", "content" => "Hello"}], result[:messages]
    assert_equal "gpt-4", result[:model]
  end

  def test_to_h_includes_additional_params
    prompt = Braintrust::Remote::Prompt.new(
      messages: [],
      model: "gpt-4",
      temperature: 0.7
    )

    result = prompt.to_h

    assert_equal 0.7, result[:temperature]
  end

  def test_to_h_excludes_nil_values
    prompt = Braintrust::Remote::Prompt.new(messages: [])

    result = prompt.to_h

    assert_equal [], result[:messages]
    refute result.key?(:model)
  end

  # ============================================
  # Hash-like access tests
  # ============================================

  def test_bracket_access_returns_value
    prompt = Braintrust::Remote::Prompt.new(
      messages: [{"role" => "user", "content" => "Hello"}],
      model: "gpt-4"
    )

    assert_equal [{"role" => "user", "content" => "Hello"}], prompt[:messages]
    assert_equal "gpt-4", prompt[:model]
  end

  def test_bracket_access_with_string_key
    prompt = Braintrust::Remote::Prompt.new(
      messages: [{"role" => "user", "content" => "Hello"}],
      model: "gpt-4"
    )

    assert_equal "gpt-4", prompt["model"]
  end

  def test_bracket_access_returns_nil_for_missing_key
    prompt = Braintrust::Remote::Prompt.new(messages: [])

    assert_nil prompt[:model]
    assert_nil prompt[:nonexistent]
  end

  # ============================================
  # to_json tests
  # ============================================

  def test_to_json_returns_json_string
    prompt = Braintrust::Remote::Prompt.new(
      messages: [{"role" => "user", "content" => "Hello"}],
      model: "gpt-4"
    )

    json = prompt.to_json
    parsed = JSON.parse(json)

    assert_equal [{"role" => "user", "content" => "Hello"}], parsed["messages"]
    assert_equal "gpt-4", parsed["model"]
  end

  # ============================================
  # Edge cases
  # ============================================

  def test_empty_messages_array
    prompt = Braintrust::Remote::Prompt.new(messages: [])

    assert_equal [], prompt.messages
  end

  def test_complex_messages
    messages = [
      {"role" => "system", "content" => "You are a helpful assistant."},
      {"role" => "user", "content" => "Hello"},
      {"role" => "assistant", "content" => "Hi there!"},
      {"role" => "user", "content" => "How are you?"}
    ]

    prompt = Braintrust::Remote::Prompt.new(messages: messages)

    assert_equal 4, prompt.messages.length
    assert_equal "system", prompt.messages[0]["role"]
  end
end
