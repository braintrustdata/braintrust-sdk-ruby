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

      # Assert that a warn_once deprecation fires for a given key during the block.
      # Clears the key from the warn_once cache before running, captures the
      # warning, then asserts it includes "deprecated".
      #
      # @param key [Symbol] The warn_once key to watch for
      # @param pattern [Regexp] Optional pattern to match against the warning message
      # @yield Block that should trigger the warning
      # @return [String] The captured warning message
      #
      # @example
      #   assert_warns_once(:eval_functions_task, /Braintrust::Functions\.task/) do
      #     Braintrust::Eval::Functions.task(project: "proj", slug: "fn")
      #   end
      #
      def assert_warns_once(key, pattern = nil)
        original_warned = Braintrust::Log.instance_variable_get(:@warned).dup
        Braintrust::Log.instance_variable_get(:@warned).delete(key)

        output = StringIO.new
        original_logger = Braintrust::Log.logger
        Braintrust::Log.logger = Logger.new(output)
        yield
        message = output.string

        assert_match(/deprecated/, message, "Expected warn_once(#{key.inspect}) to emit a deprecation warning")
        assert_match(pattern, message, "Warning did not match #{pattern.inspect}") if pattern

        message
      ensure
        Braintrust::Log.logger = original_logger
        Braintrust::Log.instance_variable_set(:@warned, original_warned)
      end
    end
  end
end
