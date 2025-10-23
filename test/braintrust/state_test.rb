# frozen_string_literal: true

require "test_helper"

class Braintrust::StateTest < Minitest::Test
  def teardown
    # Reset global state after each test
    Braintrust::State.instance_variable_set(:@global_state, nil)
  end

  def test_creates_state_with_required_fields
    state = Braintrust::State.new(
      api_key: "test-key",
      default_project: "test-project"
    )

    assert_equal "test-key", state.api_key
    assert_equal "test-project", state.default_project
  end

  def test_validates_required_api_key
    error = assert_raises(ArgumentError) do
      Braintrust::State.new(default_project: "test")
    end

    assert_match(/api_key is required/, error.message)
  end

  def test_global_state_getter_and_setter
    state = Braintrust::State.new(api_key: "global-key")

    Braintrust::State.global = state

    assert_equal state, Braintrust::State.global
  end

  def test_global_state_is_thread_safe
    # Test that concurrent access doesn't cause race conditions
    state1 = Braintrust::State.new(api_key: "key1")
    state2 = Braintrust::State.new(api_key: "key2")

    threads = []
    errors = []

    100.times do
      threads << Thread.new do
        Braintrust::State.global = state1
        retrieved = Braintrust::State.global
        # If not thread-safe, we might get nil or wrong state
        errors << "Got nil" if retrieved.nil?
      rescue => e
        errors << e.message
      end

      threads << Thread.new do
        Braintrust::State.global = state2
        retrieved = Braintrust::State.global
        errors << "Got nil" if retrieved.nil?
      rescue => e
        errors << e.message
      end
    end

    threads.each(&:join)

    # No errors should have occurred
    assert_equal [], errors

    # Final state should be one of the two states (last set wins)
    final_state = Braintrust::State.global
    assert_includes ["key1", "key2"], final_state.api_key
  end
end
