# frozen_string_literal: true

require "test_helper"
require "braintrust/internal/time"

class Braintrust::Internal::TimeTest < Minitest::Test
  Time = Braintrust::Internal::Time

  # --- measure with block ---

  def test_measure_with_block_returns_elapsed_time
    elapsed = Time.measure { sleep 0.01 }

    assert_kind_of Float, elapsed
    assert elapsed >= 0.01, "Expected elapsed >= 0.01, got #{elapsed}"
    assert elapsed < 0.1, "Expected elapsed < 0.1, got #{elapsed}"
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

  def test_measure_without_args_returns_monotonic_time
    time1 = Time.measure
    time2 = Time.measure

    assert_kind_of Float, time1
    assert_kind_of Float, time2
    assert time2 >= time1, "Monotonic time should not go backwards"
  end

  def test_measure_without_args_returns_positive_value
    time = Time.measure

    assert time > 0, "Monotonic time should be positive"
  end

  # --- measure with start_time ---

  def test_measure_with_start_time_returns_elapsed
    start = Time.measure
    sleep 0.01
    elapsed = Time.measure(start)

    assert_kind_of Float, elapsed
    assert elapsed >= 0.01, "Expected elapsed >= 0.01, got #{elapsed}"
    assert elapsed < 0.1, "Expected elapsed < 0.1, got #{elapsed}"
  end

  def test_measure_with_start_time_returns_non_negative
    start = Time.measure
    elapsed = Time.measure(start)

    assert elapsed >= 0, "Elapsed time should be non-negative"
  end

  # --- monotonic behavior ---

  def test_measure_is_monotonic
    times = 10.times.map { Time.measure }

    times.each_cons(2) do |t1, t2|
      assert t2 >= t1, "Monotonic time should never decrease"
    end
  end

  def test_measure_returns_seconds_as_float
    start = Time.measure
    sleep 0.05
    elapsed = Time.measure(start)

    # Should be roughly 0.05 seconds, not 50 milliseconds or 50_000_000 nanoseconds
    assert elapsed >= 0.04, "Expected seconds, got #{elapsed} (too small, might be wrong unit)"
    assert elapsed < 0.2, "Expected seconds, got #{elapsed} (too large, might be wrong unit)"
  end

  # --- equivalence of block and start_time modes ---

  def test_block_and_start_time_modes_equivalent
    # Both modes should measure approximately the same duration
    block_elapsed = Time.measure { sleep 0.02 }

    start = Time.measure
    sleep 0.02
    manual_elapsed = Time.measure(start)

    # Both should be close to 0.02 seconds
    assert_in_delta block_elapsed, manual_elapsed, 0.01,
      "Block and start_time modes should produce similar results"
  end
end
