# frozen_string_literal: true

module Braintrust
  module Internal
    # Time utilities using the monotonic clock for accurate duration measurements.
    #
    # Unlike Time.now, the monotonic clock is not affected by system clock adjustments
    # (NTP updates, daylight saving, manual changes) and provides accurate elapsed time.
    #
    # @see https://blog.dnsimple.com/2018/03/elapsed-time-with-ruby-the-right-way/
    module Time
      # Measure elapsed time using the monotonic clock.
      #
      # Three modes of operation:
      #
      # 1. With a block: executes the block and returns elapsed time in seconds
      #    elapsed = Time.measure { some_operation }
      #
      # 2. Without arguments: returns the current monotonic time (for later comparison)
      #    start = Time.measure
      #    # ... later ...
      #    elapsed = Time.measure(start)
      #
      # 3. With a start_time argument: returns elapsed time since start_time
      #    start = Time.measure
      #    elapsed = Time.measure(start)
      #
      # @param start_time [Float, nil] Optional start time from a previous measure call
      # @yield Optional block to measure
      # @return [Float] Elapsed time in seconds, or current monotonic time if no args/block
      def self.measure(start_time = nil)
        if block_given?
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          yield
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        elsif start_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        else
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
