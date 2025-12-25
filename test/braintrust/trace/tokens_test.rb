# frozen_string_literal: true

require "test_helper"
require "braintrust/trace/tokens"

class TokensTest < Minitest::Test
  def test_anthropic_maps_input_output_tokens
    usage = {"input_tokens" => 10, "output_tokens" => 20}

    metrics = Braintrust::Trace.parse_anthropic_usage_tokens(usage)

    assert_equal 10, metrics["prompt_tokens"]
    assert_equal 20, metrics["completion_tokens"]
    assert_equal 30, metrics["tokens"]
  end

  def test_anthropic_maps_cache_tokens
    usage = {
      "input_tokens" => 10,
      "output_tokens" => 20,
      "cache_read_input_tokens" => 50,
      "cache_creation_input_tokens" => 5
    }

    metrics = Braintrust::Trace.parse_anthropic_usage_tokens(usage)

    assert_equal 50, metrics["prompt_cached_tokens"]
    assert_equal 5, metrics["prompt_cache_creation_tokens"]
  end

  def test_anthropic_accumulates_cache_into_prompt_tokens
    usage = {
      "input_tokens" => 10,
      "output_tokens" => 20,
      "cache_read_input_tokens" => 50,
      "cache_creation_input_tokens" => 5
    }

    metrics = Braintrust::Trace.parse_anthropic_usage_tokens(usage)

    # prompt_tokens = 10 + 50 + 5 = 65
    assert_equal 65, metrics["prompt_tokens"]
  end

  def test_anthropic_calculates_total_with_cache
    usage = {
      "input_tokens" => 10,
      "output_tokens" => 20,
      "cache_read_input_tokens" => 50,
      "cache_creation_input_tokens" => 5
    }

    metrics = Braintrust::Trace.parse_anthropic_usage_tokens(usage)

    # tokens = (10 + 50 + 5) + 20 = 85
    assert_equal 85, metrics["tokens"]
  end

  def test_anthropic_returns_empty_hash_for_nil
    assert_equal({}, Braintrust::Trace.parse_anthropic_usage_tokens(nil))
  end

  def test_anthropic_handles_ruby_llm_simplified_cache_fields
    usage = {
      "input_tokens" => 10,
      "output_tokens" => 20,
      "cached_tokens" => 50,
      "cache_creation_tokens" => 5
    }

    metrics = Braintrust::Trace.parse_anthropic_usage_tokens(usage)

    assert_equal 50, metrics["prompt_cached_tokens"]
    assert_equal 5, metrics["prompt_cache_creation_tokens"]
    assert_equal 65, metrics["prompt_tokens"]
    assert_equal 85, metrics["tokens"]
  end
end
