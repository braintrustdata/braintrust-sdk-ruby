module Test
  module Support
    module AssertHelper
      # Build a chain of mocks for nested method calls.
      # Useful for testing code that traverses object hierarchies like `obj.foo.bar.baz`.
      #
      # Creates intermediate mocks that return each other in sequence, with the final
      # mock returning the specified terminal value. All intermediate mocks are verified
      # after the block. The caller is responsible for verifying the terminal value if needed.
      #
      # @param methods [Array<Symbol>] chain of method names to mock
      # @param returns [Object] the value returned by the final method (can be a Class, Mock, or any object)
      # @yield [root] the root mock (entry point to the chain)
      #
      # @example Testing a method chain with a Class as terminal
      #   fake_singleton = Class.new { include SomeModule }
      #   mock_chain(:chat, :completions, :singleton_class, returns: fake_singleton) do |client|
      #     assert SomePatcher.patched?(target: client)
      #   end
      #
      # @example Testing a method chain with a Mock as terminal
      #   terminal = Minitest::Mock.new
      #   terminal.expect(:include, true, [SomeModule])
      #   mock_chain(:foo, :bar, returns: terminal) do |root|
      #     SomeCode.do_something(root)
      #   end
      #   terminal.verify
      #
      def mock_chain(*methods, returns:)
        current = returns
        mocks = []

        methods.reverse_each do |method|
          mock = Minitest::Mock.new
          mock.expect(method, current)
          mocks.unshift(mock)
          current = mock
        end

        yield(mocks.first)

        mocks.each(&:verify)
      end

      # Runs the test inside a fork, to isolate its side-effects from the main process.
      # Similar in purpose to https://docs.ruby-lang.org/en/master/Ruby/Box.html#class-Ruby::Box
      #
      # Yields to the block for actual test code.
      # @yield Block containing the test code
      def assert_in_fork(fork_assertions: nil, timeout_seconds: 10, trigger_stacktrace_on_kill: false, debug: false)
        fork_assertions ||= proc { |status:, stdout:, stderr:|
          assert (status && status.success?), "STDOUT:`#{stdout}` STDERR:`#{stderr}"
        }

        if debug
          rv = assert_in_fork_debug(fork_assertions: fork_assertions) do
            yield
          end
          return rv
        end

        fork_stdout = Tempfile.new("braintrust-minitest-assert-in-fork-stdout")
        fork_stderr = Tempfile.new("braintrust-minitest-assert-in-fork-stderr")
        begin
          # Start in fork
          pid = fork do
            # Capture forked output
            $stdout.reopen(fork_stdout)
            $stdout.sync = true
            $stderr.reopen(fork_stderr) # STDERR captures failures. We print it in case the fork fails on exit.
            $stderr.sync = true

            yield
          end

          # Wait for fork to finish, retrieve its status.
          # Enforce timeout to ensure test fork doesn't hang the test suite.
          _, status = try_wait_until(seconds: timeout_seconds) { Process.wait2(pid, Process::WNOHANG) }

          stdout = File.read(fork_stdout.path)
          stderr = File.read(fork_stderr.path)

          # Capture forked execution information
          result = {status: status, stdout: stdout, stderr: stderr}

          # Check if fork and assertions have completed successfully
          fork_assertions.call(**result)

          result
        rescue => e
          crash_note = nil

          if trigger_stacktrace_on_kill
            crash_note = " (Crashing Ruby to get stacktrace as requested by `trigger_stacktrace_on_kill`)"
            begin
              Process.kill("SEGV", pid)
              warn "Waiting for child process to exit after SEGV signal... #{crash_note}"
              Process.wait(pid)
            rescue
              nil
            end
          end

          stdout = File.read(fork_stdout.path)
          stderr = File.read(fork_stderr.path)

          raise "Failure or timeout in `assert_in_fork`#{crash_note}, STDOUT: `#{stdout}`, STDERR: `#{stderr}`", cause: e
        ensure
          begin
            Process.kill("KILL", pid)
          rescue
            nil
          end # Prevent zombie processes on failure

          fork_stderr.close
          fork_stdout.close
          fork_stdout.unlink
          fork_stderr.unlink
        end
      end

      # Debug version of assert_in_fork that does not redirect I/O streams and
      # has no timeout on execution. The idea is to use it for interactive
      # debugging where you would set a break point in the fork.
      def assert_in_fork_debug(fork_assertions:, timeout_seconds: 10, trigger_stacktrace_on_kill: false)
        pid = fork do
          yield
        end
        _, status = Process.wait2(pid)
        fork_assertions.call(status: status, stdout: "", stderr: "")
      end

      # Waits for the condition provided by the block argument to return truthy.
      #
      # Waits for 5 seconds by default.
      #
      # Can be configured by setting either:
      #   * `seconds`, or
      #   * `attempts` and `backoff`
      #
      # @yieldreturn [Boolean] block executed until it returns truthy
      # @param [Numeric] seconds number of seconds to wait
      # @param [Integer] attempts number of attempts at checking the condition
      # @param [Numeric] backoff wait time between condition checking attempts
      def try_wait_until(seconds: nil, attempts: nil, backoff: nil)
        raise "Provider either `seconds` or `attempts` & `backoff`, not both" if seconds && (attempts || backoff)

        spec = if seconds
          "#{seconds} seconds"
        elsif attempts || backoff
          "#{attempts} attempts with backoff: #{backoff}"
        else
          "none"
        end

        if seconds
          attempts = seconds * 10
          backoff = 0.1
        else
          # 5 seconds by default, but respect the provide values if any.
          attempts ||= 50
          backoff ||= 0.1
        end

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # It's common for tests to want to run simple tasks in a background thread
        # but call this method without the thread having even time to start.
        #
        # We add an extra attempt, interleaved by `Thread.pass`, in order to allow for
        # those simple cases to quickly succeed without a timed `sleep` call. This will
        # save simple test one `backoff` seconds sleep cycle.
        #
        # The total configured timeout is not reduced.
        (attempts + 1).times do |i|
          result = yield(attempts)
          return result if result

          if i == 0
            Thread.pass
          else
            sleep(backoff)
          end
        end

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        actual = "#{"%.2f" % elapsed} seconds, #{attempts} attempts with backoff #{backoff}"

        raise("Wait time exhausted! Requested: #{spec}, waited: #{actual}")
      end
    end
  end
end
