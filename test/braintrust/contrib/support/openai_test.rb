# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/support/openai"

class Braintrust::Contrib::Support::OpenAITest < Minitest::Test
  # ===================
  # parse_usage_tokens
  # ===================

  def test_maps_standard_fields
    usage = {"prompt_tokens" => 10, "completion_tokens" => 20, "total_tokens" => 30}

    metrics = Braintrust::Contrib::Support::OpenAI.parse_usage_tokens(usage)

    assert_equal 10, metrics["prompt_tokens"]
    assert_equal 20, metrics["completion_tokens"]
    assert_equal 30, metrics["tokens"]
  end

  def test_handles_symbol_keys
    usage = {prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}

    metrics = Braintrust::Contrib::Support::OpenAI.parse_usage_tokens(usage)

    assert_equal 10, metrics["prompt_tokens"]
  end

  def test_handles_prompt_tokens_details
    usage = {
      "prompt_tokens" => 100,
      "prompt_tokens_details" => {"cached_tokens" => 80}
    }

    metrics = Braintrust::Contrib::Support::OpenAI.parse_usage_tokens(usage)

    assert_equal 80, metrics["prompt_cached_tokens"]
  end

  def test_handles_completion_tokens_details
    usage = {
      "completion_tokens" => 50,
      "completion_tokens_details" => {"reasoning_tokens" => 30}
    }

    metrics = Braintrust::Contrib::Support::OpenAI.parse_usage_tokens(usage)

    assert_equal 30, metrics["completion_reasoning_tokens"]
  end

  def test_handles_object_style_token_details
    # OpenAI SDK returns objects with to_h, not plain hashes
    details_object = Struct.new(:cached_tokens, :audio_tokens, keyword_init: true)
    usage_object = Struct.new(:prompt_tokens, :completion_tokens, :total_tokens, :prompt_tokens_details, keyword_init: true)

    usage = usage_object.new(
      prompt_tokens: 100,
      completion_tokens: 50,
      total_tokens: 150,
      prompt_tokens_details: details_object.new(cached_tokens: 80, audio_tokens: 0)
    )

    metrics = Braintrust::Contrib::Support::OpenAI.parse_usage_tokens(usage)

    assert_equal 80, metrics["prompt_cached_tokens"]
    assert_equal 0, metrics["prompt_audio_tokens"]
  end

  def test_returns_empty_hash_for_nil
    assert_equal({}, Braintrust::Contrib::Support::OpenAI.parse_usage_tokens(nil))
  end

  def test_calculates_total_if_missing
    usage = {"prompt_tokens" => 10, "completion_tokens" => 20}

    metrics = Braintrust::Contrib::Support::OpenAI.parse_usage_tokens(usage)

    assert_equal 30, metrics["tokens"]
  end

  def test_handles_responses_api_field_names
    # Responses API uses input_tokens/output_tokens
    usage = {"input_tokens" => 10, "output_tokens" => 20}

    metrics = Braintrust::Contrib::Support::OpenAI.parse_usage_tokens(usage)

    assert_equal 10, metrics["prompt_tokens"]
    assert_equal 20, metrics["completion_tokens"]
    assert_equal 30, metrics["tokens"]
  end
end
