# frozen_string_literal: true

require "test_helper"
require "braintrust/server"
require "json"
require "stringio"

class Braintrust::Server::Handlers::EvalTest < Minitest::Test
  def setup
    @evaluators = {}
    @rig = setup_otel_test_rig
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
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    status, _, _ = handler.call(rack_json_env({name: "test-eval"}, path: "/eval"))
    assert_equal 400, status
  end

  def test_returns_400_for_multiple_data_sources
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    status, _, _ = handler.call(rack_json_env(
      {name: "test-eval", data: {data: [{input: "x"}], dataset_name: "ds"}},
      path: "/eval"
    ))
    assert_equal 400, status
  end

  # --- SSE streaming ---

  def test_returns_200_with_sse_content_type
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    status, headers, _ = handler.call(rack_json_env(
      {name: "test-eval", data: {data: [{input: "hello"}]}, experiment_name: "exp"},
      path: "/eval"
    ))

    assert_equal 200, status
    assert_equal "text/event-stream", headers["content-type"]
    assert_equal "no-cache", headers["cache-control"]
    assert_equal "keep-alive", headers["connection"]
  end

  def test_streams_progress_event_per_case
    @evaluators["upcase-eval"] = test_evaluator(task: ->(input) { input.to_s.upcase })

    _, _, body = handler.call(rack_json_env(
      {name: "upcase-eval", data: {data: [{input: "a"}, {input: "b"}, {input: "c"}]}, experiment_name: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    progress = events.select { |e| e[:event] == "progress" }

    # 2 progress events per case: json_delta + done
    assert_equal 6, progress.length
  end

  def test_progress_event_contains_protocol_fields
    @evaluators["upcase-eval"] = test_evaluator(task: ->(input) { input.to_s.upcase })

    _, _, body = handler.call(rack_json_env(
      {name: "upcase-eval", data: {data: [{input: "hello"}]}, experiment_name: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    progress = events.find { |e| e[:event] == "progress" }
    data = JSON.parse(progress[:data])

    assert_equal "task", data["object_type"]
    assert_equal "upcase-eval", data["name"]
    assert_equal "code", data["format"]
    assert_equal "completion", data["output_type"]
    assert_equal "json_delta", data["event"]
    assert data.key?("id"), "Progress event should include span id"
  end

  def test_progress_event_contains_task_output_as_json_string
    @evaluators["upcase-eval"] = test_evaluator(task: ->(input) { input.to_s.upcase })

    _, _, body = handler.call(rack_json_env(
      {name: "upcase-eval", data: {data: [{input: "hello"}]}, experiment_name: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    progress = events.find { |e| e[:event] == "progress" }
    data = JSON.parse(progress[:data])

    # data field is JSON-encoded (matches Java SDK / UI protocol)
    assert_equal "\"HELLO\"", data["data"]
    assert_equal "HELLO", JSON.parse(data["data"])
  end

  def test_progress_event_excludes_scores
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }
    @evaluators["scored-eval"] = test_evaluator(
      task: ->(input) { input.to_s.upcase },
      scorers: [scorer]
    )

    _, _, body = handler.call(rack_json_env(
      {name: "scored-eval", data: {data: [{input: "hello", expected: "HELLO"}]}, experiment_name: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    progress = events.find { |e| e[:event] == "progress" }
    data = JSON.parse(progress[:data])

    # Scores are delivered via OTLP spans, not in progress events (matches Java SDK)
    refute data.key?("scores"), "Progress events should not include scores"
  end

  def test_summary_event_contains_scores_and_experiment_name
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }
    @evaluators["scored-eval"] = test_evaluator(
      task: ->(input) { input.to_s.upcase },
      scorers: [scorer]
    )

    _, _, body = handler.call(rack_json_env(
      {name: "scored-eval", data: {data: [{input: "hello", expected: "HELLO"}]}, experiment_name: "my-experiment"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    summary = events.find { |e| e[:event] == "summary" }
    data = JSON.parse(summary[:data])

    assert data.key?("scores")
    assert_equal "my-experiment", data["experiment_name"]
  end

  def test_stream_ends_with_done
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    _, _, body = handler.call(rack_json_env(
      {name: "test-eval", data: {data: [{input: "x"}]}, experiment_name: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    assert_equal "done", events.last[:event]
  end

  def test_task_error_still_emits_progress_and_done
    @evaluators["failing-eval"] = test_evaluator(task: ->(_) { raise "boom" })

    _, _, body = handler.call(rack_json_env(
      {name: "failing-eval", data: {data: [{input: "x"}]}, experiment_name: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)

    assert events.any? { |e| e[:event] == "progress" }
    assert_equal "done", events.last[:event]
  end

  def test_task_error_progress_contains_error_event
    @evaluators["failing-eval"] = test_evaluator(task: ->(_) { raise "task exploded" })

    _, _, body = handler.call(rack_json_env(
      {name: "failing-eval", data: {data: [{input: "x"}]}, experiment_name: "exp"},
      path: "/eval"
    ))

    events = collect_sse_events(body)
    progress = events.find { |e| e[:event] == "progress" }
    data = JSON.parse(progress[:data])

    assert_equal "error", data["event"]
    assert_match(/task exploded/, data["data"])
  end

  # --- Data source validation ---

  def test_returns_400_for_dataset_id_plus_inline_data
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    status, _, _ = handler.call(rack_json_env(
      {name: "test-eval", data: {data: [{input: "x"}], dataset_id: "ds-123"}},
      path: "/eval"
    ))
    assert_equal 400, status
  end

  def test_accepts_dataset_id_as_sole_data_source
    # This should return 200 (SSE stream) but will fail inside evaluator.run
    # because no API client is available. We just check it passes validation.
    @evaluators["test-eval"] = test_evaluator(
      task: ->(input) { input },
      scorers: [Braintrust::Eval.scorer("s") { |i, e, o| 1.0 }]
    )

    status, headers, _ = handler.call(rack_json_env(
      {name: "test-eval", data: {dataset_id: "ds-123"}},
      path: "/eval"
    ))

    # Returns 200 because validation passed — the SSE body will contain the error
    assert_equal 200, status
    assert_equal "text/event-stream", headers["content-type"]
  end

  # --- Auth passthrough ---

  def test_build_state_returns_nil_without_auth
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    env = rack_json_env(
      {name: "test-eval", data: {data: [{input: "hello"}]}},
      path: "/eval"
    )

    # No braintrust.auth set — should still work (state will be nil)
    status, _, _ = handler.call(env)
    assert_equal 200, status
  end

  def test_build_state_returns_nil_for_non_hash_auth
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    env = rack_json_env(
      {name: "test-eval", data: {data: [{input: "hello"}]}},
      path: "/eval"
    )
    # NoAuth strategy returns `true`, not a Hash
    env["braintrust.auth"] = true

    status, _, _ = handler.call(env)
    assert_equal 200, status
  end

  def test_handler_passes_state_when_auth_present
    received_opts = nil
    spy_evaluator = test_evaluator(
      task: ->(input) { input },
      scorers: [Braintrust::Eval.scorer("s") { |i, e, o| 1.0 }]
    )

    # Replace evaluator.run with a spy that captures kwargs and returns a fake result
    spy_evaluator.define_singleton_method(:run) do |cases, **opts|
      received_opts = opts
      Braintrust::Eval::Result.new(
        experiment_id: nil, experiment_name: nil,
        project_id: nil, project_name: nil,
        permalink: nil, scores: {}, errors: [], duration: 0.01
      )
    end

    @evaluators["spy-eval"] = spy_evaluator

    env = rack_json_env(
      {
        name: "spy-eval",
        data: {data: [{input: "hello"}]},
        experiment_name: "my-exp",
        project_id: "proj-123"
      },
      path: "/eval"
    )
    env["braintrust.auth"] = {
      "api_key" => "test-key",
      "org_id" => "test-org-id",
      "org_name" => "test-org",
      "app_url" => "https://app.example.com",
      "api_url" => "https://api.example.com"
    }

    status, _, body = handler.call(env)
    # Drain the SSE body to trigger evaluation
    body.each { |_| }

    assert_equal 200, status
    assert_instance_of Braintrust::State, received_opts[:state],
      "Handler should pass State when auth is present"
    assert_equal "my-exp", received_opts[:experiment]
    assert_equal "proj-123", received_opts[:project_id]
  end

  def test_handler_does_not_pass_state_without_auth
    received_opts = nil
    spy_evaluator = test_evaluator(
      task: ->(input) { input },
      scorers: [Braintrust::Eval.scorer("s") { |i, e, o| 1.0 }]
    )

    spy_evaluator.define_singleton_method(:run) do |cases, **opts|
      received_opts = opts
      Braintrust::Eval::Result.new(
        experiment_id: nil, experiment_name: nil,
        project_id: nil, project_name: nil,
        permalink: nil, scores: {}, errors: [], duration: 0.01
      )
    end

    @evaluators["spy-eval"] = spy_evaluator

    env = rack_json_env(
      {name: "spy-eval", data: {data: [{input: "hello"}]}, experiment_name: "exp"},
      path: "/eval"
    )
    # No braintrust.auth set

    status, _, body = handler.call(env)
    body.each { |_| }

    assert_equal 200, status
    assert_nil received_opts[:state],
      "Handler should not pass state when no auth"
  end

  # --- State caching ---

  def test_build_state_caches_by_auth_key
    h = handler

    auth = {
      "api_key" => "key-1",
      "org_id" => "org-1",
      "org_name" => "org",
      "app_url" => "https://app.example.com",
      "api_url" => "https://api.example.com"
    }

    env1 = {"braintrust.auth" => auth}
    env2 = {"braintrust.auth" => auth}

    state1 = h.send(:build_state, env1)
    state2 = h.send(:build_state, env2)

    assert_same state1, state2, "Same auth should return cached State"
  end

  def test_build_state_returns_different_state_for_different_auth
    h = handler

    auth_a = {
      "api_key" => "key-a",
      "org_id" => "org-a",
      "org_name" => "org-a",
      "app_url" => "https://app.example.com",
      "api_url" => "https://api.example.com"
    }
    auth_b = {
      "api_key" => "key-b",
      "org_id" => "org-b",
      "org_name" => "org-b",
      "app_url" => "https://app.example.com",
      "api_url" => "https://api.example.com"
    }

    state_a = h.send(:build_state, {"braintrust.auth" => auth_a})
    state_b = h.send(:build_state, {"braintrust.auth" => auth_b})

    refute_same state_a, state_b, "Different auth should return different State"
  end

  def test_build_state_evicts_oldest_when_cache_full
    h = handler

    # Fill cache to capacity (64 entries)
    65.times do |i|
      auth = {
        "api_key" => "key-#{i}",
        "org_id" => "org-#{i}",
        "org_name" => "org-#{i}",
        "app_url" => "https://app.example.com",
        "api_url" => "https://api.example.com"
      }
      h.send(:build_state, {"braintrust.auth" => auth})
    end

    # First entry (key-0) should have been evicted
    cache = h.instance_variable_get(:@state_cache)

    assert_equal 64, cache.size, "Cache should not exceed 64 entries"
    refute cache.key?(["key-0", "https://app.example.com", "org-0"]),
      "Oldest entry should have been evicted"
  end

  # --- Remote scorers ---

  def test_handler_resolves_scores_to_scorer_ids
    # Verify the handler can accept scores array and pass through.
    # Since no API is available, remote scorers will fail at resolution time,
    # but we verify the request doesn't fail at validation.
    @evaluators["test-eval"] = test_evaluator(
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
        scores: [{"function_id" => "func-123"}]
      },
      path: "/eval"
    ))

    assert_equal 200, status
  end

  # --- Server-specific body selection ---

  def test_returns_sse_body_without_protocol_http_request
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    _, _, body = handler.call(rack_json_env(
      {name: "test-eval", data: {data: [{input: "x"}]}, experiment_name: "exp"},
      path: "/eval"
    ))

    assert_instance_of Braintrust::Server::SSEBody, body
  end

  def test_returns_sse_stream_body_with_protocol_http_request
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    env = rack_json_env(
      {name: "test-eval", data: {data: [{input: "x"}]}, experiment_name: "exp"},
      path: "/eval"
    )
    # Simulate protocol-rack env key (set by Falcon and other protocol-http servers)
    env["protocol.http.request"] = Object.new

    _, _, body = handler.call(env)

    assert_instance_of Braintrust::Server::SSEStreamBody, body
  end

  # --- Parent passthrough ---

  def test_handler_passes_parent_through
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    _, _, body = handler.call(rack_json_env(
      {
        name: "test-eval",
        data: {data: [{input: "hello"}]},
        parent: {"object_type" => "project_logs", "object_id" => "proj-789"}
      },
      path: "/eval"
    ))

    events = collect_sse_events(body)

    # Should complete successfully (progress + summary + done)
    assert events.any? { |e| e[:event] == "progress" }
    assert_equal "done", events.last[:event]
  end

  private

  def test_evaluator(**kwargs)
    Test::Support::EvalHelper::TestEvaluator.new(tracer_provider: @rig.tracer_provider, **kwargs)
  end

  def handler
    Braintrust::Server::Handlers::Eval.new(@evaluators)
  end
end
