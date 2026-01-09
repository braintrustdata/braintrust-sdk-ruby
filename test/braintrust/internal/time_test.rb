# frozen_string_literal: true

require "test_helper"
require "braintrust/internal/time"

class Braintrust::Internal::TimeTest < Minitest::Test
  Time = Braintrust::Internal::Time

  # --- measure with block ---

  def test_measure_with_block_returns_float
    elapsed = Time.measure { 1 + 1 }

    assert_kind_of Float, elapsed
    assert elapsed >= 0
  end

  def test_measure_with_block_executes_block
    executed = false
    Time.measure { executed = true }

    assert executed, "Block should have been executed"
  end

  def test_measure_with_block_returns_time_not_block_result
    result = Time.measure { "block result" }

    assert_kind_of Float, result
    refute_equal "block result", result
  end

  # --- measure without arguments ---

  def test_measure_without_args_returns_float
    time = Time.measure

    assert_kind_of Float, time
    assert time > 0, "Monotonic time should be positive"
  end

  # --- measure with start_time ---

  def test_measure_with_start_time_returns_float
    start = Time.measure
    elapsed = Time.measure(start)

    assert_kind_of Float, elapsed
    assert elapsed >= 0
  end
end
