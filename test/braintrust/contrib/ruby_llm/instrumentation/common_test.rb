# frozen_string_literal: true

require "test_helper"
require "braintrust/contrib/ruby_llm/instrumentation/common"

class Braintrust::Contrib::RubyLLM::Instrumentation::CommonTest < Minitest::Test
  Common = Braintrust::Contrib::RubyLLM::Instrumentation::Common
  Message = Struct.new(:counts) do
    def to_h = counts
  end

  # =======================
  # message_usage_metrics
  # =======================

  def test_reads_ruby_llm_2_cache_keys
    message = Message.new({input_tokens: 3, output_tokens: 26, cache_read_tokens: 2763, cache_write_tokens: 366})

    metrics = Common.message_usage_metrics(message)

    assert_equal 2763, metrics["prompt_cached_tokens"]
    assert_equal 366, metrics["prompt_cache_creation_tokens"]
    assert_equal 3132, metrics["prompt_tokens"]
    assert_equal 26, metrics["completion_tokens"]
    assert_equal 3158, metrics["tokens"]
  end

  def test_reads_ruby_llm_1_cache_keys
    message = Message.new({input_tokens: 10, output_tokens: 5, cached_tokens: 40, cache_creation_tokens: 50})

    metrics = Common.message_usage_metrics(message)

    assert_equal 40, metrics["prompt_cached_tokens"]
    assert_equal 50, metrics["prompt_cache_creation_tokens"]
    assert_equal 100, metrics["prompt_tokens"]
    assert_equal 105, metrics["tokens"]
  end

  def test_returns_empty_without_counts
    assert_empty Common.message_usage_metrics(Message.new({role: :assistant}))
  end

  def test_returns_empty_when_message_has_no_to_h
    assert_empty Common.message_usage_metrics(Object.new)
  end
end
