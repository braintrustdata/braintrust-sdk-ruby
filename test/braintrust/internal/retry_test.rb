# frozen_string_literal: true

require "test_helper"
require "braintrust/internal/retry"

class Braintrust::Internal::RetryTest < Minitest::Test
  # ============================================
  # Without until: (truthiness mode)
  # ============================================

  def test_returns_immediately_on_truthy_result
    call_count = 0
    result = Braintrust::Internal::Retry.with_backoff(max_retries: 3) {
      call_count += 1
      "done"
    }
    assert_equal "done", result
    assert_equal 1, call_count
  end

  def test_retries_on_falsy_then_returns_truthy
    call_count = 0
    result = Braintrust::Internal::Retry.with_backoff(max_retries: 5, base_delay: 0.001) {
      call_count += 1
      (call_count >= 3) ? "got it" : nil
    }
    assert_equal "got it", result
    assert_equal 3, call_count
  end

  def test_returns_last_falsy_result_when_retries_exhausted
    call_count = 0
    result = Braintrust::Internal::Retry.with_backoff(max_retries: 2, base_delay: 0.001) {
      call_count += 1
      nil
    }
    assert_nil result
    assert_equal 3, call_count # 1 initial + 2 retries
  end

  # ============================================
  # With until: (condition mode)
  # ============================================

  def test_until_stops_on_satisfied_condition
    call_count = 0
    result = Braintrust::Internal::Retry.with_backoff(
      max_retries: 5,
      base_delay: 0.001,
      until: ->(r) { r[:ready] }
    ) {
      call_count += 1
      {ready: call_count >= 2, value: call_count}
    }
    assert_equal({ready: true, value: 2}, result)
    assert_equal 2, call_count
  end

  def test_until_returns_last_result_when_retries_exhausted
    call_count = 0
    result = Braintrust::Internal::Retry.with_backoff(
      max_retries: 2,
      base_delay: 0.001,
      until: ->(r) { r[:ready] }
    ) {
      call_count += 1
      {ready: false, value: call_count}
    }
    assert_equal({ready: false, value: 3}, result)
    assert_equal 3, call_count
  end

  def test_until_returns_immediately_when_first_attempt_satisfies
    call_count = 0
    result = Braintrust::Internal::Retry.with_backoff(
      max_retries: 5,
      until: ->(r) { r == "ok" }
    ) {
      call_count += 1
      "ok"
    }
    assert_equal "ok", result
    assert_equal 1, call_count
  end

  def test_until_allows_falsy_block_result_to_be_returned
    # until: condition is separate from truthiness, so a falsy result can be "done"
    result = Braintrust::Internal::Retry.with_backoff(
      max_retries: 3,
      until: ->(_r) { true }
    ) { nil }
    assert_nil result
  end

  # ============================================
  # Backoff timing
  # ============================================

  def test_exponential_backoff_with_cap
    delays = []
    Braintrust::Internal::Retry.stub(:sleep, ->(d) { delays << d }) do
      Braintrust::Internal::Retry.with_backoff(
        max_retries: 5,
        base_delay: 1.0,
        max_delay: 4.0
      ) { nil }
    end
    # Schedule: 1, 2, 4, 4, 4
    assert_equal [1.0, 2.0, 4.0, 4.0, 4.0], delays
  end

  def test_no_sleep_when_first_attempt_succeeds
    delays = []
    Braintrust::Internal::Retry.stub(:sleep, ->(d) { delays << d }) do
      Braintrust::Internal::Retry.with_backoff(max_retries: 5) { "done" }
    end
    assert_empty delays
  end
end
