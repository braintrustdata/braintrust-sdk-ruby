# frozen_string_literal: true

require "test_helper"
require "braintrust/server"
require "json"
require "stringio"

class Braintrust::Server::Handlers::EvalTest < Minitest::Test
  def setup
    @evaluators = {}
  end

  # --- Request validation ---

  def test_returns_400_for_missing_body
    status, _, _ = handler.call(rack_env_with_body(nil, path: "/eval"))
    assert_equal 400, status
  end

  def test_returns_400_for_invalid_json
    status, _, _ = handler.call(rack_env_with_body("not json", path: "/eval"))
    assert_equal 400, status
  end

  def test_returns_400_for_missing_name
    status, _, _ = handler.call(rack_json_env({data: {data: []}}, path: "/eval"))
    assert_equal 400, status
  end

  def test_returns_404_for_unknown_evaluator
    status, _, body = handler.call(rack_json_env({name: "nonexistent", data: {data: []}}, path: "/eval"))

    assert_equal 404, status
    parsed = JSON.parse(body.first)
    assert_match(/not found/i, parsed["error"])
  end

  def test_returns_400_for_missing_data
    @evaluators["test-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    status, _, _ = handler.call(rack_json_env({name: "test-eval"}, path: "/eval"))
    assert_equal 400, status
  end

  def test_returns_400_for_multiple_data_sources
    @evaluators["test-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    status, _, _ = handler.call(rack_json_env(
      {name: "test-eval", data: {data: [{input: "x"}], datasetName: "ds"}},
      path: "/eval"
    ))
    assert_equal 400, status
  end

  # --- SSE streaming ---

  def test_returns_200_with_sse_content_type
    @evaluators["test-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    status, headers, _ = handler.call(rack_json_env(
      {name: "test-eval", data: {data: [{input: "hello"}]}, experimentName: "exp"},
      path: "/eval"
    ))

    assert_equal 200, status
    assert_equal "text/event-stream", headers["content-type"]
  end

  def test_streams_progress_event_per_case
    @evaluators["upcase-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input.to_s.upcase })

    _, _, body = handler.call(rack_json_env(
      {name: "upcase-eval", data: {data: [{input: "a"}, {input: "b"}, {input: "c"}]}, experimentName: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    progress = events.select { |e| e[:event] == "progress" }

    assert_equal 3, progress.length
  end

  def test_progress_event_contains_task_output
    @evaluators["upcase-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input.to_s.upcase })

    _, _, body = handler.call(rack_json_env(
      {name: "upcase-eval", data: {data: [{input: "hello"}]}, experimentName: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    progress = events.find { |e| e[:event] == "progress" }
    data = JSON.parse(progress[:data])

    assert_equal "HELLO", data["data"]
  end

  def test_progress_event_contains_scores
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }
    @evaluators["scored-eval"] = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input.to_s.upcase },
      scorers: [scorer]
    )

    _, _, body = handler.call(rack_json_env(
      {name: "scored-eval", data: {data: [{input: "hello", expected: "HELLO"}]}, experimentName: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    progress = events.find { |e| e[:event] == "progress" }
    data = JSON.parse(progress[:data])

    assert_equal 1.0, data["scores"]["exact"]
  end

  def test_summary_event_contains_scores_and_experiment_name
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }
    @evaluators["scored-eval"] = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input.to_s.upcase },
      scorers: [scorer]
    )

    _, _, body = handler.call(rack_json_env(
      {name: "scored-eval", data: {data: [{input: "hello", expected: "HELLO"}]}, experimentName: "my-experiment"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    summary = events.find { |e| e[:event] == "summary" }
    data = JSON.parse(summary[:data])

    assert data.key?("scores")
    assert_equal "my-experiment", data["experimentName"]
  end

  def test_stream_ends_with_done
    @evaluators["test-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    _, _, body = handler.call(rack_json_env(
      {name: "test-eval", data: {data: [{input: "x"}]}, experimentName: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    assert_equal "done", events.last[:event]
  end

  def test_task_error_still_emits_progress_and_done
    @evaluators["failing-eval"] = Braintrust::Eval::Evaluator.new(task: ->(_) { raise "boom" })

    _, _, body = handler.call(rack_json_env(
      {name: "failing-eval", data: {data: [{input: "x"}]}, experimentName: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)

    assert events.any? { |e| e[:event] == "progress" }
    assert_equal "done", events.last[:event]
  end

  def test_task_error_progress_contains_error_message
    @evaluators["failing-eval"] = Braintrust::Eval::Evaluator.new(task: ->(_) { raise "task exploded" })

    _, _, body = handler.call(rack_json_env(
      {name: "failing-eval", data: {data: [{input: "x"}]}, experimentName: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    progress = events.find { |e| e[:event] == "progress" }
    data = JSON.parse(progress[:data])

    assert_match(/task exploded/, data["error"])
  end

  # --- Data source validation ---

  def test_returns_400_for_datasetId_plus_inline_data
    @evaluators["test-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    status, _, _ = handler.call(rack_json_env(
      {name: "test-eval", data: {data: [{input: "x"}], datasetId: "ds-123"}},
      path: "/eval"
    ))
    assert_equal 400, status
  end

  def test_accepts_datasetId_as_sole_data_source
    # This should return 200 (SSE stream) but will fail inside evaluator.run
    # because no API client is available. We just check it passes validation.
    @evaluators["test-eval"] = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input },
      scorers: [Braintrust::Eval.scorer("s") { |i, e, o| 1.0 }]
    )

    status, headers, _ = handler.call(rack_json_env(
      {name: "test-eval", data: {datasetId: "ds-123"}},
      path: "/eval"
    ))

    # Returns 200 because validation passed — the SSE body will contain the error
    assert_equal 200, status
    assert_equal "text/event-stream", headers["content-type"]
  end

  # --- Auth passthrough ---

  def test_build_api_returns_nil_without_auth
    @evaluators["test-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    env = rack_json_env(
      {name: "test-eval", data: {data: [{input: "hello"}]}},
      path: "/eval"
    )

    # No braintrust.auth set — should still work (api will be nil)
    status, _, _ = handler.call(env)
    assert_equal 200, status
  end

  def test_build_api_returns_nil_for_non_hash_auth
    @evaluators["test-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    env = rack_json_env(
      {name: "test-eval", data: {data: [{input: "hello"}]}},
      path: "/eval"
    )
    # NoAuth strategy returns `true`, not a Hash
    env["braintrust.auth"] = true

    status, _, _ = handler.call(env)
    assert_equal 200, status
  end

  # --- Remote scorers ---

  def test_handler_resolves_scores_to_scorer_ids
    # Verify the handler can accept scores array and pass through.
    # Since no API is available, remote scorers will fail at resolution time,
    # but we verify the request doesn't fail at validation.
    @evaluators["test-eval"] = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input },
      scorers: [Braintrust::Eval.scorer("local") { |i, e, o| 1.0 }]
    )

    # With inline data + scores — should return 200 (SSE stream)
    # The actual ScorerId resolution will fail inside the stream since no API,
    # but it should not fail at handler validation level
    status, _, _ = handler.call(rack_json_env(
      {
        name: "test-eval",
        data: {data: [{input: "hello"}]},
        scores: [{"functionId" => "func-123"}]
      },
      path: "/eval"
    ))

    assert_equal 200, status
  end

  # --- Parent passthrough ---

  def test_handler_passes_parent_through
    @evaluators["test-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    _, _, body = handler.call(rack_json_env(
      {
        name: "test-eval",
        data: {data: [{input: "hello"}]},
        parent: {"objectType" => "project_logs", "objectId" => "proj-789"}
      },
      path: "/eval"
    ))

    events = collect_sse_events(body)

    # Should complete successfully (progress + summary + done)
    assert events.any? { |e| e[:event] == "progress" }
    assert_equal "done", events.last[:event]
  end

  private

  def handler
    Braintrust::Server::Handlers::Eval.new(@evaluators)
  end
end
