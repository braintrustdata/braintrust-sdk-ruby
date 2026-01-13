# frozen_string_literal: true

require "test_helper"

# NOTE: braintrust/setup.rb triggers Braintrust::Setup.run! when required,
# so all tests must run in a fork to isolate side effects.
class Braintrust::SetupTest < Minitest::Test
  # --- run! ---

  def test_run_calls_braintrust_init
    assert_in_fork do
      require "braintrust/contrib/setup"

      init_called = false

      with_stubs(
        [Braintrust, :init, ->(**_kwargs) { init_called = true }],
        [Braintrust::Contrib::Setup, :run!, -> {}]
      ) do
        require "braintrust/setup"
      end

      assert init_called, "Braintrust.init should be called"
    end
  end

  def test_run_calls_contrib_setup_run
    assert_in_fork do
      require "braintrust/contrib/setup"

      contrib_setup_called = false

      with_stubs(
        [Braintrust, :init, ->(**_kwargs) {}],
        [Braintrust::Contrib::Setup, :run!, -> { contrib_setup_called = true }]
      ) do
        require "braintrust/setup"
      end

      assert contrib_setup_called, "Contrib::Setup.run! should be called"
    end
  end

  def test_run_is_idempotent
    assert_in_fork do
      require "braintrust/contrib/setup"

      call_count = 0

      with_stubs(
        [Braintrust, :init, ->(**_kwargs) { call_count += 1 }],
        [Braintrust::Contrib::Setup, :run!, -> {}]
      ) do
        require "braintrust/setup"

        # First call happens during require, try calling again
        Braintrust::Setup.run!
        Braintrust::Setup.run!
      end

      assert_equal 1, call_count, "init should only be called once"
    end
  end

  def test_run_logs_error_on_init_failure
    assert_in_fork do
      require "braintrust/contrib/setup"

      logged_messages = []

      with_stubs(
        [Braintrust, :init, ->(**_kwargs) { raise "Test init error" }],
        [Braintrust::Log, :error, ->(msg) { logged_messages << msg }],
        [Braintrust::Contrib::Setup, :run!, -> {}]
      ) do
        require "braintrust/setup"
      end

      error_logged = logged_messages.any? do |msg|
        msg.include?("Failed to automatically setup Braintrust") &&
          msg.include?("Test init error")
      end

      assert error_logged, "should log error message containing failure details"
    end
  end

  def test_run_continues_to_contrib_setup_after_init_failure
    assert_in_fork do
      require "braintrust/contrib/setup"

      contrib_setup_called = false

      with_stubs(
        [Braintrust, :init, ->(**_kwargs) { raise "Test init error" }],
        [Braintrust::Log, :error, ->(_msg) {}],
        [Braintrust::Contrib::Setup, :run!, -> { contrib_setup_called = true }]
      ) do
        require "braintrust/setup"
      end

      assert contrib_setup_called, "Contrib::Setup.run! should be called even after init failure"
    end
  end
end
