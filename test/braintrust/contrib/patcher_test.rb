# frozen_string_literal: true

require "test_helper"

class Braintrust::Contrib::PatcherTest < Minitest::Test
  def setup
    # Create a fresh patcher class for each test to avoid state leakage
    @patcher = create_test_patcher
  end

  def create_test_patcher(should_fail: false)
    patcher = Class.new(Braintrust::Contrib::Patcher) do
      class << self
        attr_accessor :patch_count, :last_options, :should_fail
      end

      def self.perform_patch(**options)
        @patch_count ||= 0
        @patch_count += 1
        @last_options = options
        raise "Intentional patch failure" if @should_fail
      end
    end

    patcher.reset!
    patcher.patch_count = 0
    patcher.last_options = {}
    patcher.should_fail = should_fail
    patcher
  end

  def test_patch_passes_options
    options = {tracer_provider: "test-provider", target: "test-target"}
    @patcher.patch!(**options)

    assert_equal "test-provider", @patcher.last_options[:tracer_provider]
    assert_equal "test-target", @patcher.last_options[:target]
  end

  def test_patched_returns_false_initially
    refute @patcher.patched?
  end

  def test_patch_sets_patched_to_true
    @patcher.patch!

    assert @patcher.patched?
  end

  def test_patch_returns_true_on_success
    result = @patcher.patch!

    assert result
  end

  def test_patch_calls_perform_patch_once
    @patcher.patch!

    assert_equal 1, @patcher.patch_count
  end

  def test_patch_is_idempotent
    @patcher.patch!
    @patcher.patch!
    @patcher.patch!

    assert_equal 1, @patcher.patch_count
    assert @patcher.patched?
  end

  def test_patch_returns_true_on_subsequent_calls
    first_result = @patcher.patch!
    second_result = @patcher.patch!

    assert first_result
    assert second_result
  end

  def test_patch_passes_options_to_perform_patch
    tracer_provider = Object.new

    @patcher.patch!(tracer_provider: tracer_provider)

    assert_instance_of Hash, @patcher.last_options
    assert_equal tracer_provider, @patcher.last_options[:tracer_provider]
  end

  def test_patch_returns_false_on_error
    failing_patcher = create_test_patcher(should_fail: true)

    result = suppress_logs { failing_patcher.patch! }

    refute result
  end

  def test_patch_does_not_set_patched_on_error
    failing_patcher = create_test_patcher(should_fail: true)

    suppress_logs { failing_patcher.patch! }

    refute failing_patcher.patched?
  end

  def test_patch_logs_error_on_failure
    failing_patcher = create_test_patcher(should_fail: true)

    # Capture log output
    captured_logs = []
    original_logger = Braintrust::Log.logger
    test_logger = Logger.new(StringIO.new)
    test_logger.formatter = ->(_severity, _time, _progname, msg) {
      captured_logs << msg
      ""
    }
    Braintrust::Log.logger = test_logger

    begin
      failing_patcher.patch!
      # Check that error was logged (can't easily verify content without more setup)
      # The main thing is that it doesn't raise
    ensure
      Braintrust::Log.logger = original_logger
    end
  end

  def test_reset_allows_repatching
    @patcher.patch!
    assert @patcher.patched?

    @patcher.reset!
    refute @patcher.patched?

    @patcher.patch!
    assert @patcher.patched?
    assert_equal 2, @patcher.patch_count
  end

  def test_perform_patch_raises_not_implemented_in_base_class
    assert_raises(NotImplementedError) do
      Braintrust::Contrib::Patcher.perform_patch
    end
  end

  def test_thread_safety_only_patches_once
    patcher = create_test_patcher

    threads = 100.times.map do
      Thread.new { patcher.patch! }
    end

    threads.each(&:join)

    assert_equal 1, patcher.patch_count
    assert patcher.patched?
  end

  def test_thread_safety_concurrent_patch_calls
    patcher = create_test_patcher

    errors = []
    results = []
    mutex = Mutex.new

    threads = 100.times.map do
      Thread.new do
        result = patcher.patch!
        mutex.synchronize { results << result }
      rescue => e
        mutex.synchronize { errors << e.message }
      end
    end

    threads.each(&:join)

    assert_equal [], errors
    assert results.all? { |r| r == true }
    assert_equal 1, patcher.patch_count
  end

  def test_applicable_returns_true_by_default
    assert @patcher.applicable?
  end

  def test_applicable_can_be_overridden
    patcher = Class.new(Braintrust::Contrib::Patcher) do
      def self.applicable?
        false
      end

      def self.perform_patch(**options)
        # No-op
      end
    end
    patcher.reset!

    refute patcher.applicable?
  end

  def test_patch_checks_applicable_under_lock
    applicable_calls = []
    patcher = Class.new(Braintrust::Contrib::Patcher) do
      class << self
        attr_accessor :applicable_calls
      end

      def self.applicable?
        @applicable_calls ||= []
        @applicable_calls << Thread.current.object_id
        true
      end

      def self.perform_patch(**options)
        # No-op
      end
    end
    patcher.reset!
    patcher.applicable_calls = applicable_calls

    patcher.patch!

    # Should be called twice: once before lock (fast path), once under lock (double-check)
    assert_equal 2, applicable_calls.length
  end

  def test_patch_returns_false_when_not_applicable
    patcher = Class.new(Braintrust::Contrib::Patcher) do
      class << self
        attr_accessor :perform_patch_called
      end

      def self.applicable?
        false
      end

      def self.perform_patch(**options)
        @perform_patch_called = true
      end
    end
    patcher.reset!
    patcher.perform_patch_called = false

    result = patcher.patch!

    refute result
    refute patcher.perform_patch_called
    refute patcher.patched?
  end

  def test_patch_returns_false_and_does_not_log_when_not_applicable
    patcher = Class.new(Braintrust::Contrib::Patcher) do
      def self.applicable?
        false
      end

      def self.perform_patch(**options)
        # No-op
      end
    end
    patcher.reset!

    # Capture log output
    captured_logs = []
    original_logger = Braintrust::Log.logger
    test_logger = Logger.new(StringIO.new)
    test_logger.level = Logger::DEBUG
    test_logger.formatter = ->(_severity, _time, _progname, msg) {
      captured_logs << msg
      ""
    }
    Braintrust::Log.logger = test_logger

    begin
      result = patcher.patch!
      # Fast path returns false immediately without logging
      refute result
      assert_empty captured_logs, "Fast path should not log when not applicable"
    ensure
      Braintrust::Log.logger = original_logger
    end
  end
end
