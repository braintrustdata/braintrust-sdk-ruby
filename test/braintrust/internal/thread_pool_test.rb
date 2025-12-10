# frozen_string_literal: true

require "test_helper"
require "braintrust/internal/thread_pool"

class Braintrust::Internal::ThreadPoolTest < Minitest::Test
  def test_each_processes_all_items
    items = [1, 2, 3, 4, 5]
    processed = Queue.new

    result = Braintrust::Internal::ThreadPool.each(items, parallelism: 3) do |item|
      processed << item
    end

    assert_nil result
    assert_equal 5, processed.size
    collected = [].tap { |a| a << processed.pop until processed.empty? }
    assert_equal items.sort, collected.sort
  end

  def test_each_parallelism_1_is_sequential
    items = [1, 2, 3]
    order = []
    mutex = Mutex.new

    Braintrust::Internal::ThreadPool.each(items, parallelism: 1) do |item|
      mutex.synchronize { order << item }
    end

    # With parallelism 1, items should be processed in order
    assert_equal [1, 2, 3], order
  end

  def test_each_default_parallelism_is_3
    assert_equal 3, Braintrust::Internal::ThreadPool::DEFAULT_PARALLELISM
  end

  def test_collect_returns_results_in_order
    items = [1, 2, 3, 4, 5]

    results = Braintrust::Internal::ThreadPool.collect(items, parallelism: 3) do |item|
      sleep(rand * 0.01) # Random delay to ensure out-of-order completion
      item * 2
    end

    assert_equal [2, 4, 6, 8, 10], results
  end

  def test_collect_parallelism_1_is_sequential
    items = [1, 2, 3]

    results = Braintrust::Internal::ThreadPool.collect(items, parallelism: 1) do |item|
      item * 2
    end

    assert_equal [2, 4, 6], results
  end

  def test_thread_safety_under_load
    items = (1..100).to_a
    results = Queue.new

    Braintrust::Internal::ThreadPool.each(items, parallelism: 10) do |item|
      results << item
    end

    assert_equal 100, results.size
    collected = [].tap { |a| a << results.pop until results.empty? }
    assert_equal items.sort, collected.sort
  end

  def test_collect_thread_safety_under_load
    items = (1..100).to_a

    results = Braintrust::Internal::ThreadPool.collect(items, parallelism: 10) do |item|
      item * 2
    end

    assert_equal 100, results.size
    assert_equal items.map { |i| i * 2 }, results
  end

  def test_invalid_parallelism_zero_raises
    assert_raises(ArgumentError) do
      Braintrust::Internal::ThreadPool.each([1, 2, 3], parallelism: 0) {}
    end
  end

  def test_invalid_parallelism_negative_raises
    assert_raises(ArgumentError) do
      Braintrust::Internal::ThreadPool.each([1, 2, 3], parallelism: -1) {}
    end
  end

  def test_invalid_parallelism_exceeds_max_raises
    max = Braintrust::Internal::ThreadPool::MAX_PARALLELISM
    error = assert_raises(ArgumentError) do
      Braintrust::Internal::ThreadPool.each([1, 2, 3], parallelism: max + 1) {}
    end
    assert_match(/cannot exceed #{max}/, error.message)
  end

  def test_invalid_parallelism_non_integer_raises
    assert_raises(ArgumentError) do
      Braintrust::Internal::ThreadPool.each([1, 2, 3], parallelism: 2.5) {}
    end
  end

  def test_invalid_strategy_raises
    error = assert_raises(ArgumentError) do
      Braintrust::Internal::ThreadPool.run([1, 2, 3], strategy: :invalid) { |i| i }
    end
    assert_match(/Unknown strategy/, error.message)
  end

  def test_empty_items_handled_each
    processed = []

    result = Braintrust::Internal::ThreadPool.each([], parallelism: 3) do |item|
      processed << item
    end

    assert_nil result
    assert_empty processed
  end

  def test_empty_items_handled_collect
    results = Braintrust::Internal::ThreadPool.collect([], parallelism: 3) do |item|
      item * 2
    end

    assert_equal [], results
  end

  def test_custom_strategy_object
    custom_strategy = Class.new do
      def prepare(items)
        @items = items
        @results = []
      end

      def enqueue_sentinel(count)
        # Not used in sequential fallback test
      end

      def work_loop(&block)
        # Not used in sequential fallback test
      end

      def result
        "custom result"
      end

      def empty_result
        "empty custom result"
      end

      def sequential_run(items, &block)
        items.each(&block)
        "custom result"
      end
    end.new

    # With parallelism 1, uses sequential_run from strategy
    result = Braintrust::Internal::ThreadPool.run([1, 2, 3], parallelism: 1, strategy: custom_strategy) do |item|
      item * 2
    end

    assert_equal "custom result", result
  end

  def test_enumerable_input_converted_to_array
    # Test with a lazy enumerator
    items = (1..5).lazy.map { |i| i }

    results = Braintrust::Internal::ThreadPool.collect(items, parallelism: 2) do |item|
      item * 2
    end

    assert_equal [2, 4, 6, 8, 10], results
  end

  def test_exceptions_in_block_propagate
    items = [1, 2, 3]

    # Suppress thread exception output for this test
    original_report = Thread.report_on_exception
    Thread.report_on_exception = false

    begin
      assert_raises(RuntimeError) do
        Braintrust::Internal::ThreadPool.each(items, parallelism: 2) do |item|
          raise "test error" if item == 2
        end
      end
    ensure
      Thread.report_on_exception = original_report
    end
  end
end

# Isolated unit tests for Each strategy
class Braintrust::Internal::ThreadPool::EachTest < Minitest::Test
  def setup
    @strategy = Braintrust::Internal::ThreadPool::Each.new
  end

  def test_prepare_populates_queue
    items = [1, 2, 3]
    @strategy.prepare(items)

    # Queue should contain all items
    collected = []
    3.times { collected << @strategy.instance_variable_get(:@queue).pop }
    assert_equal [1, 2, 3], collected
  end

  def test_enqueue_sentinel_adds_done_markers
    @strategy.prepare([])
    @strategy.enqueue_sentinel(3)

    queue = @strategy.instance_variable_get(:@queue)
    3.times { assert_equal :done, queue.pop }
  end

  def test_work_loop_processes_items_until_done
    @strategy.prepare([1, 2, 3])
    @strategy.enqueue_sentinel(1)

    processed = []
    @strategy.work_loop { |item| processed << item }

    assert_equal [1, 2, 3], processed
  end

  def test_work_loop_stops_on_done_sentinel
    @strategy.prepare([1])
    @strategy.enqueue_sentinel(1)

    call_count = 0
    @strategy.work_loop { |_| call_count += 1 }

    assert_equal 1, call_count
  end

  def test_result_returns_nil
    @strategy.prepare([1, 2, 3])
    assert_nil @strategy.result
  end
end

# Isolated unit tests for Collect strategy
class Braintrust::Internal::ThreadPool::CollectTest < Minitest::Test
  def setup
    @strategy = Braintrust::Internal::ThreadPool::Collect.new
  end

  def test_prepare_populates_queue_with_indexed_items
    items = [:a, :b, :c]
    @strategy.prepare(items)

    queue = @strategy.instance_variable_get(:@queue)
    collected = []
    3.times { collected << queue.pop }

    assert_equal [[:a, 0], [:b, 1], [:c, 2]], collected
  end

  def test_prepare_initializes_results_array
    items = [1, 2, 3]
    @strategy.prepare(items)

    results = @strategy.instance_variable_get(:@results)
    assert_equal 3, results.size
    assert_equal [nil, nil, nil], results
  end

  def test_enqueue_sentinel_adds_done_markers
    @strategy.prepare([])
    @strategy.enqueue_sentinel(2)

    queue = @strategy.instance_variable_get(:@queue)
    2.times { assert_equal :done, queue.pop }
  end

  def test_work_loop_stores_results_at_correct_indices
    @strategy.prepare([:a, :b, :c])
    @strategy.enqueue_sentinel(1)

    @strategy.work_loop { |item| "processed_#{item}" }

    results = @strategy.instance_variable_get(:@results)
    assert_equal ["processed_a", "processed_b", "processed_c"], results
  end

  def test_work_loop_handles_out_of_order_processing
    @strategy.prepare([:a, :b, :c])

    # Manually simulate out-of-order processing
    queue = @strategy.instance_variable_get(:@queue)

    # Pop all items
    work_items = []
    3.times { work_items << queue.pop }

    # Process in reverse order (simulating threads finishing out of order)
    work_items.reverse_each do |item, idx|
      @strategy.instance_variable_get(:@results)[idx] = "result_#{item}"
    end

    assert_equal ["result_a", "result_b", "result_c"], @strategy.result
  end

  def test_result_returns_results_array
    @strategy.prepare([1, 2])
    @strategy.enqueue_sentinel(1)

    @strategy.work_loop { |item| item * 10 }

    assert_equal [10, 20], @strategy.result
  end

  def test_result_preserves_input_order
    items = [3, 1, 2]
    @strategy.prepare(items)
    @strategy.enqueue_sentinel(1)

    @strategy.work_loop { |item| item * 2 }

    # Results should be in same order as input, not sorted
    assert_equal [6, 2, 4], @strategy.result
  end
end
