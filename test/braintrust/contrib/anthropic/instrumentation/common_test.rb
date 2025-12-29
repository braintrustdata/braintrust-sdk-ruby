# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/anthropic/instrumentation/common"

class Braintrust::Contrib::Anthropic::Instrumentation::CommonTest < Minitest::Test
  Common = Braintrust::Contrib::Anthropic::Instrumentation::Common

  # ===================
  # parse_usage_tokens
  # ===================

  def test_maps_standard_fields
    usage = {"input_tokens" => 10, "output_tokens" => 20}

    metrics = Common.parse_usage_tokens(usage)

    assert_equal 10, metrics["prompt_tokens"]
    assert_equal 20, metrics["completion_tokens"]
    assert_equal 30, metrics["tokens"]
  end

  def test_handles_symbol_keys
    usage = {input_tokens: 10, output_tokens: 20}

    metrics = Common.parse_usage_tokens(usage)

    assert_equal 10, metrics["prompt_tokens"]
    assert_equal 20, metrics["completion_tokens"]
  end

  def test_handles_cache_read_tokens
    usage = {
      "input_tokens" => 100,
      "output_tokens" => 50,
      "cache_read_input_tokens" => 80
    }

    metrics = Common.parse_usage_tokens(usage)

    assert_equal 80, metrics["prompt_cached_tokens"]
    # prompt_tokens should include cache tokens
    assert_equal 180, metrics["prompt_tokens"]
  end

  def test_handles_cache_creation_tokens
    usage = {
      "input_tokens" => 100,
      "output_tokens" => 50,
      "cache_creation_input_tokens" => 20
    }

    metrics = Common.parse_usage_tokens(usage)

    assert_equal 20, metrics["prompt_cache_creation_tokens"]
    # prompt_tokens should include cache creation tokens
    assert_equal 120, metrics["prompt_tokens"]
  end

  def test_handles_object_with_to_h
    # SDK returns objects with to_h method
    usage_object = Struct.new(:input_tokens, :output_tokens, keyword_init: true)
    usage = usage_object.new(input_tokens: 10, output_tokens: 20)

    metrics = Common.parse_usage_tokens(usage)

    assert_equal 10, metrics["prompt_tokens"]
    assert_equal 20, metrics["completion_tokens"]
  end

  def test_returns_empty_hash_for_nil
    assert_equal({}, Common.parse_usage_tokens(nil))
  end

  def test_returns_empty_hash_for_non_hash
    assert_equal({}, Common.parse_usage_tokens("invalid"))
  end

  def test_calculates_total
    usage = {"input_tokens" => 10, "output_tokens" => 20}

    metrics = Common.parse_usage_tokens(usage)

    assert_equal 30, metrics["tokens"]
  end

  def test_total_includes_cache_tokens
    usage = {
      "input_tokens" => 100,
      "output_tokens" => 50,
      "cache_read_input_tokens" => 80,
      "cache_creation_input_tokens" => 20
    }

    metrics = Common.parse_usage_tokens(usage)

    # Total = prompt_tokens (which includes cache) + completion_tokens
    # prompt_tokens = 100 + 80 + 20 = 200
    # tokens = 200 + 50 = 250
    assert_equal 250, metrics["tokens"]
  end
end
