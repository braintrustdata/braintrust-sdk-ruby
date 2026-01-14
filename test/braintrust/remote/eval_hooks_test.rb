# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::EvalHooksTest < Minitest::Test
  # ============================================
  # Constructor tests
  # ============================================

  def test_initializes_with_empty_defaults
    hooks = Braintrust::Remote::EvalHooks.new

    assert_equal({}, hooks.parameters)
    assert_equal({}, hooks.metadata)
  end

  def test_initializes_with_parameters
    params = {model: "gpt-4", temperature: 0.7}
    hooks = Braintrust::Remote::EvalHooks.new(parameters: params)

    assert_equal params, hooks.parameters
  end

  def test_initializes_with_metadata
    metadata = {session_id: "123", user_id: "456"}
    hooks = Braintrust::Remote::EvalHooks.new(metadata: metadata)

    assert_equal metadata, hooks.metadata
  end

  def test_initializes_with_stream_callback
    callback = ->(event) { puts event }
    hooks = Braintrust::Remote::EvalHooks.new(stream_callback: callback)

    # Stream callback is stored internally
    assert_instance_of Braintrust::Remote::EvalHooks, hooks
  end

  # ============================================
  # set_metadata tests
  # ============================================

  def test_set_metadata_adds_key_value
    hooks = Braintrust::Remote::EvalHooks.new(metadata: {})

    hooks.set_metadata(:key, "value")

    assert_equal "value", hooks.metadata[:key]
  end

  def test_set_metadata_overwrites_existing_key
    hooks = Braintrust::Remote::EvalHooks.new(metadata: {key: "old"})

    hooks.set_metadata(:key, "new")

    assert_equal "new", hooks.metadata[:key]
  end

  def test_set_metadata_with_string_key
    hooks = Braintrust::Remote::EvalHooks.new(metadata: {})

    hooks.set_metadata("string_key", "value")

    # String keys are converted to symbols
    assert_equal "value", hooks.metadata[:string_key]
  end

  # ============================================
  # report_progress tests
  # ============================================

  def test_report_progress_calls_stream_callback
    events = []
    callback = ->(event) { events << event }
    hooks = Braintrust::Remote::EvalHooks.new(stream_callback: callback)

    hooks.report_progress({type: "progress", value: 50})

    assert_equal 1, events.length
    assert_equal({type: "progress", value: 50}, events[0])
  end

  def test_report_progress_does_nothing_without_callback
    hooks = Braintrust::Remote::EvalHooks.new

    # Should not raise
    hooks.report_progress({type: "progress", value: 50})
  end

  def test_report_progress_with_multiple_events
    events = []
    callback = ->(event) { events << event }
    hooks = Braintrust::Remote::EvalHooks.new(stream_callback: callback)

    hooks.report_progress({step: 1})
    hooks.report_progress({step: 2})
    hooks.report_progress({step: 3})

    assert_equal 3, events.length
  end

  # ============================================
  # Parameters access tests
  # ============================================

  def test_parameters_can_be_read
    params = {model: "gpt-4"}
    hooks = Braintrust::Remote::EvalHooks.new(parameters: params)

    # Parameters can be read
    assert_equal "gpt-4", hooks.parameters[:model]
  end

  def test_parameters_reference_is_shared
    params = {model: "gpt-4"}
    hooks = Braintrust::Remote::EvalHooks.new(parameters: params)

    # Hooks stores a reference to the params hash
    assert_equal params.object_id, hooks.parameters.object_id
  end

  # ============================================
  # Integration-like tests
  # ============================================

  def test_typical_usage_pattern
    events = []
    callback = ->(event) { events << event }

    hooks = Braintrust::Remote::EvalHooks.new(
      parameters: {
        model: "gpt-4",
        temperature: 0.7
      },
      metadata: {
        request_id: "req-123"
      },
      stream_callback: callback
    )

    # Task function accesses parameters
    model = hooks.parameters[:model]
    assert_equal "gpt-4", model

    # Task function reports progress
    hooks.report_progress({status: "processing"})
    assert_equal 1, events.length

    # Task function sets metadata
    hooks.set_metadata(:latency_ms, 150)
    assert_equal 150, hooks.metadata[:latency_ms]

    # Original metadata is preserved
    assert_equal "req-123", hooks.metadata[:request_id]
  end
end
