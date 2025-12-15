module Test
  module Support
    module LogHelper
      # Suppress log output during block execution.
      # Use for tests that deliberately cause errors/warnings.
      #
      # @yield Block to execute with logging suppressed
      # @return Result of the block
      #
      # @example
      #   suppress_logs { failing_patcher.patch! }
      #
      def suppress_logs
        original_logger = Braintrust::Log.logger
        Braintrust::Log.logger = Logger.new(File::NULL)
        yield
      ensure
        Braintrust::Log.logger = original_logger
      end
    end
  end
end
