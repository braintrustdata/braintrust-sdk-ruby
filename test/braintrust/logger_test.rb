# frozen_string_literal: true

require "test_helper"
require "braintrust/logger"

class Braintrust::LoggerTest < Minitest::Test
  def setup
    @output = StringIO.new
    @original_logger = Braintrust::Log.logger
    @original_warned = Braintrust::Log.instance_variable_get(:@warned).dup
    Braintrust::Log.logger = Logger.new(@output, level: Logger::DEBUG)
    Braintrust::Log.instance_variable_set(:@warned, Set.new)
  end

  def teardown
    Braintrust::Log.logger = @original_logger
    Braintrust::Log.instance_variable_set(:@warned, @original_warned)
  end

  # ============================================
  # Basic log levels
  # ============================================

  def test_debug_writes_message
    Braintrust::Log.debug("debug msg")
    assert_includes @output.string, "debug msg"
  end

  def test_info_writes_message
    Braintrust::Log.info("info msg")
    assert_includes @output.string, "info msg"
  end

  def test_warn_writes_message
    Braintrust::Log.warn("warn msg")
    assert_includes @output.string, "warn msg"
  end

  def test_error_writes_message
    Braintrust::Log.error("error msg")
    assert_includes @output.string, "error msg"
  end

  # ============================================
  # warn_once
  # ============================================

  def test_warn_once_emits_on_first_call
    Braintrust::Log.warn_once(:test_key, "first warning")
    assert_includes @output.string, "first warning"
  end

  def test_warn_once_suppresses_duplicate_key
    Braintrust::Log.warn_once(:dup_key, "first")
    Braintrust::Log.warn_once(:dup_key, "second")

    assert_includes @output.string, "first"
    refute_includes @output.string, "second"
  end

  def test_warn_once_allows_different_keys
    Braintrust::Log.warn_once(:key_a, "warning A")
    Braintrust::Log.warn_once(:key_b, "warning B")

    assert_includes @output.string, "warning A"
    assert_includes @output.string, "warning B"
  end

  # ============================================
  # logger is swappable
  # ============================================

  def test_logger_accessor
    new_output = StringIO.new
    Braintrust::Log.logger = Logger.new(new_output)

    Braintrust::Log.warn("after swap")

    refute_includes @output.string, "after swap"
    assert_includes new_output.string, "after swap"
  end
end
