# frozen_string_literal: true

require "test_helper"

class WithoutOpenAITest < Minitest::Test
  def test_sdk_loads_without_openai_gem
    # This test verifies that the core SDK can be loaded without the openai gem
    # Skip this test if we're in the with-openai appraisal
    skip "Test only runs in without-openai appraisal" if openai_available?

    # If we got here, the SDK loaded successfully (via test_helper.rb)
    assert true, "SDK loaded without openai gem"
  end

  def test_core_functionality_without_openai
    skip "Test only runs in without-openai appraisal" if openai_available?

    # Test that we can initialize Braintrust without tracing (no OpenAI needed)
    state = Braintrust.init(
      api_key: "test-key",
      set_global: false,
      blocking_login: false,
      tracing: false
    )

    assert_instance_of Braintrust::State, state
    assert_equal "test-key", state.api_key
  end

  def test_openai_require_fails_without_gem
    skip "Test only runs in without-openai appraisal" if openai_available?

    # Attempting to require openai should fail if gem not installed
    assert_raises(LoadError) do
      require "openai"
    end
  end

  def test_openai_trace_wrapper_not_available_without_gem
    skip "Test only runs in without-openai appraisal" if openai_available?

    # The OpenAI trace wrapper should not be automatically loaded
    # It should only load when explicitly required
    refute defined?(OpenAI), "OpenAI should not be defined without the gem"
  end

  private

  # Check if OpenAI gem is available (used for skipping tests in wrong appraisal)
  def openai_available?
    require "openai"
    true
  rescue LoadError
    false
  end
end
