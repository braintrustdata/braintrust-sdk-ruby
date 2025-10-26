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

  def test_init_accepts_autoinstrument_parameter
    # Test that Braintrust.init accepts autoinstrument parameter and passes it through
    state = Braintrust.init(
      api_key: "test-key",
      set_global: false,
      enable_tracing: false,  # Disable tracing to avoid setup overhead
      autoinstrument: {enabled: true}
    )

    # Verify state was created successfully with autoinstrument config
    assert_instance_of Braintrust::State, state
    assert_equal({enabled: true, include: nil, exclude: nil}, state.autoinstrument_config)
  end

  def test_autoinstrument_defaults_to_disabled
    # Test that when autoinstrument is nil, it defaults to disabled
    state = Braintrust.init(
      api_key: "test-key",
      set_global: false,
      enable_tracing: false
    )

    assert_equal({enabled: false}, state.autoinstrument_config)
  end

  def test_autoinstrument_enabled_false_explicit
    # Test that { enabled: false } is stored correctly
    state = Braintrust.init(
      api_key: "test-key",
      set_global: false,
      enable_tracing: false,
      autoinstrument: {enabled: false}
    )

    assert_equal({enabled: false}, state.autoinstrument_config)
  end

  def test_autoinstrument_with_include_list
    # Test that include list is validated and stored
    state = Braintrust.init(
      api_key: "test-key",
      set_global: false,
      enable_tracing: false,
      autoinstrument: {enabled: true, include: [:openai, :anthropic]}
    )

    assert_equal({enabled: true, include: [:openai, :anthropic], exclude: nil}, state.autoinstrument_config)
  end

  def test_autoinstrument_with_exclude_list
    # Test that exclude list is validated and stored
    state = Braintrust.init(
      api_key: "test-key",
      set_global: false,
      enable_tracing: false,
      autoinstrument: {enabled: true, exclude: [:anthropic]}
    )

    assert_equal({enabled: true, include: nil, exclude: [:anthropic]}, state.autoinstrument_config)
  end

  def test_autoinstrument_rejects_both_include_and_exclude
    # Test that both include and exclude raises error
    error = assert_raises(ArgumentError) do
      Braintrust.init(
        api_key: "test-key",
        set_global: false,
        enable_tracing: false,
        autoinstrument: {enabled: true, include: [:openai], exclude: [:anthropic]}
      )
    end

    assert_match(/cannot specify both.*include.*exclude/i, error.message)
  end

  def test_autoinstrument_rejects_include_without_enabled
    # Test that include without enabled: true raises error
    error = assert_raises(ArgumentError) do
      Braintrust.init(
        api_key: "test-key",
        set_global: false,
        enable_tracing: false,
        autoinstrument: {include: [:openai]}
      )
    end

    assert_match(/include.*requires.*enabled.*true/i, error.message)
  end

  def test_autoinstrument_rejects_exclude_without_enabled
    # Test that exclude without enabled: true raises error
    error = assert_raises(ArgumentError) do
      Braintrust.init(
        api_key: "test-key",
        set_global: false,
        enable_tracing: false,
        autoinstrument: {exclude: [:anthropic]}
      )
    end

    assert_match(/exclude.*requires.*enabled.*true/i, error.message)
  end

  def test_autoinstrument_rejects_non_array_include
    # Test that non-array include raises error
    error = assert_raises(ArgumentError) do
      Braintrust.init(
        api_key: "test-key",
        set_global: false,
        enable_tracing: false,
        autoinstrument: {enabled: true, include: :openai}
      )
    end

    assert_match(/include.*must be an array/i, error.message)
  end

  def test_autoinstrument_rejects_non_symbol_include
    # Test that non-symbol values in include raises error
    error = assert_raises(ArgumentError) do
      Braintrust.init(
        api_key: "test-key",
        set_global: false,
        enable_tracing: false,
        autoinstrument: {enabled: true, include: ["openai"]}
      )
    end

    assert_match(/include.*must contain.*symbols/i, error.message)
  end
end
