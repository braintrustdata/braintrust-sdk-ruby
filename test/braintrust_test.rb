# frozen_string_literal: true

require "test_helper"

class BraintrustTest < Minitest::Test
  def setup
    # Save original env var
    @original_api_key = ENV["BRAINTRUST_API_KEY"]
  end

  def teardown
    # Reset global state after each test
    Braintrust::State.instance_variable_set(:@global_state, nil)

    # Restore original env var
    if @original_api_key
      ENV["BRAINTRUST_API_KEY"] = @original_api_key
    else
      ENV.delete("BRAINTRUST_API_KEY")
    end
  end

  def test_init_sets_global_state_by_default
    ENV["BRAINTRUST_API_KEY"] = "test-key"

    Braintrust.init

    state = Braintrust.current_state
    assert_equal "test-key", state.api_key
  end

  def test_init_with_set_global_false_returns_state
    ENV["BRAINTRUST_API_KEY"] = "test-key"

    # Ensure global state is clean before test
    Braintrust::State.instance_variable_set(:@global_state, nil)

    state = Braintrust.init(set_global: false)

    assert_equal "test-key", state.api_key
    assert_nil Braintrust.current_state
  end

  def test_init_merges_options_with_env
    ENV["BRAINTRUST_API_KEY"] = "env-key"

    Braintrust.init(api_key: "explicit-key", default_parent: "project_name:my-project")

    state = Braintrust.current_state
    assert_equal "explicit-key", state.api_key
    assert_equal "project_name:my-project", state.default_parent
  end
end
