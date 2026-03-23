# frozen_string_literal: true

module Braintrust
  module Internal
    module Retry
      MAX_RETRIES = 7
      BASE_DELAY = 1.0
      MAX_DELAY = 8.0

      # Retry a block with exponential backoff.
      #
      # The block is the task to attempt. Its return value is captured each attempt.
      #
      # @param max_retries [Integer] Maximum number of retries after the first attempt
      # @param base_delay [Float] Initial delay in seconds (doubles each retry)
      # @param max_delay [Float] Cap on delay between retries
      # @param until [Proc, nil] Optional condition — receives block result, truthy stops retrying.
      #   When omitted, the block result's own truthiness decides.
      # @return The last block result (whether retries were exhausted or condition was met)
      #
      # @example Simple: retry until truthy
      #   conn = Retry.with_backoff(max_retries: 5) { try_connect }
      #
      # @example With condition: retry until non-empty
      #   data = Retry.with_backoff(until: ->(r) { r.any? }) { api.fetch }
      #
      def self.with_backoff(max_retries: MAX_RETRIES, base_delay: BASE_DELAY, max_delay: MAX_DELAY, until: nil, &task)
        check = binding.local_variable_get(:until)
        result = task.call
        retries = 0
        while retries < max_retries && !(check ? check.call(result) : result)
          retries += 1
          delay = [base_delay * (2**(retries - 1)), max_delay].min
          sleep(delay)
          result = task.call
        end
        result
      end
    end
  end
end
