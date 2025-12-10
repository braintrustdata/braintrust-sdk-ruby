# frozen_string_literal: true

module Braintrust
  module Internal
    # Reusable thread pool for concurrent task execution.
    # Uses the strategy pattern to define result handling behavior.
    #
    # @example Iterate without collecting results (Eval use case)
    #   ThreadPool.each(items, parallelism: 4) do |item|
    #     process(item)
    #   end
    #
    # @example Collect results in order
    #   results = ThreadPool.collect(items, parallelism: 4) do |item|
    #     transform(item)
    #   end
    #
    # @note Thread limits are per-call, not global. If your application calls
    #   ThreadPool methods from multiple threads concurrently (e.g., web workers,
    #   background jobs), each call spawns its own worker threads. Plan your
    #   parallelism settings accordingly to avoid excessive thread creation.
    #
    class ThreadPool
      DEFAULT_PARALLELISM = 3
      MAX_PARALLELISM = 50

      # Strategy for iteration without collecting results
      class Each
        def prepare(items)
          @queue = Queue.new
          items.each { |item| @queue << item }
        end

        def enqueue_sentinel(count)
          count.times { @queue << :done }
        end

        def work_loop(&block)
          loop do
            item = @queue.pop
            break if item == :done
            block.call(item)
          end
        end

        def result
          nil
        end

        def empty_result
          nil
        end

        def sequential_run(items, &block)
          items.each(&block)
          nil
        end
      end

      # Strategy for collecting results in input order
      class Collect
        def prepare(items)
          @results = Array.new(items.size)
          @queue = Queue.new
          items.each_with_index { |item, idx| @queue << [item, idx] }
        end

        def enqueue_sentinel(count)
          count.times { @queue << :done }
        end

        def work_loop(&block)
          loop do
            work = @queue.pop
            break if work == :done
            item, idx = work
            @results[idx] = block.call(item)
          end
        end

        def result
          @results
        end

        def empty_result
          []
        end

        def sequential_run(items, &block)
          items.map(&block)
        end
      end

      STRATEGIES = {
        each: Each,
        collect: Collect
      }.freeze

      # Execute block for each item concurrently, discarding results.
      # @param items [Array, Enumerable] Items to process
      # @param parallelism [Integer] Number of worker threads (default: 3)
      # @yield [item] Block to execute for each item
      # @return [nil]
      def self.each(items, parallelism: DEFAULT_PARALLELISM, &block)
        run(items, parallelism: parallelism, strategy: :each, &block)
      end

      # Execute block for each item concurrently, collecting results in order.
      # @param items [Array, Enumerable] Items to process
      # @param parallelism [Integer] Number of worker threads (default: 3)
      # @yield [item] Block to execute for each item
      # @return [Array] Results in same order as input items
      def self.collect(items, parallelism: DEFAULT_PARALLELISM, &block)
        run(items, parallelism: parallelism, strategy: :collect, &block)
      end

      # Execute block for each item concurrently using the specified strategy.
      # Prefer using .each or .collect convenience methods instead.
      # @param items [Array, Enumerable] Items to process
      # @param strategy [Symbol, #prepare] Strategy for result handling (required)
      # @param parallelism [Integer] Number of worker threads (default: 3)
      # @yield [item] Block to execute for each item
      # @return [Object, nil] Strategy-dependent result
      def self.run(items, strategy:, parallelism: DEFAULT_PARALLELISM, &block)
        validate_parallelism!(parallelism)

        executor = strategy_instance(strategy)
        all_items = items.to_a

        return executor.sequential_run(all_items, &block) if parallelism == 1
        return executor.empty_result if all_items.empty?

        executor.prepare(all_items)
        executor.enqueue_sentinel(parallelism)

        threads = parallelism.times.map do
          Thread.new { executor.work_loop(&block) }
        end

        threads.each(&:join)
        executor.result
      end

      def self.strategy_instance(strategy)
        case strategy
        when Symbol
          STRATEGIES.fetch(strategy) {
            raise ArgumentError, "Unknown strategy: #{strategy}. Valid: #{STRATEGIES.keys.join(", ")}"
          }.new
        else
          strategy
        end
      end

      def self.validate_parallelism!(parallelism)
        unless parallelism.is_a?(Integer) && parallelism > 0
          raise ArgumentError, "parallelism must be a positive integer"
        end
        if parallelism > MAX_PARALLELISM
          raise ArgumentError, "parallelism cannot exceed #{MAX_PARALLELISM}"
        end
      end

      private_class_method :strategy_instance, :validate_parallelism!
    end
  end
end
