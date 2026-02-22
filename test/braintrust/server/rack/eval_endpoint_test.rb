# frozen_string_literal: true

require "test_helper"
require "braintrust/server"
require "rack/test"
require "json"

# Integration tests for POST /eval through the full Rack middleware stack.
class Braintrust::Server::Rack::EvalEndpointTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @evaluators = {}
    @rig = setup_otel_test_rig
  end

  def app
    Braintrust::Server::Rack.app(evaluators: @evaluators, auth: :none)
  end

  def test_streams_sse_events_for_inline_data
    @evaluators["upcase-eval"] = test_evaluator(task: ->(input) { input.to_s.upcase })

    post_json "/eval", {
      name: "upcase-eval",
      data: {
        data: [
          {input: "hello", expected: "HELLO"},
          {input: "world", expected: "WORLD"}
        ]
      },
      experiment_name: "test-experiment",
      project_id: "proj-123",
      parent: {object_type: "playground_id", object_id: "pg-123"}
    }

    assert_equal 200, last_response.status
    assert_equal "text/event-stream", last_response.content_type

    events = parse_sse_events(last_response.body)

    progress_events = events.select { |e| e[:event] == "progress" }
    assert_equal 2, progress_events.length

    summary_events = events.select { |e| e[:event] == "summary" }
    assert_equal 1, summary_events.length

    assert_equal "done", events.last[:event]
  end

  def test_progress_events_contain_output
    @evaluators["upcase-eval"] = test_evaluator(task: ->(input) { input.to_s.upcase })

    post_json "/eval", {
      name: "upcase-eval",
      data: {data: [{input: "hello", expected: "HELLO"}]},
      experiment_name: "test-experiment",
      project_id: "proj-123",
      parent: {object_type: "playground_id", object_id: "pg-123"}
    }

    events = parse_sse_events(last_response.body)
    progress = events.find { |e| e[:event] == "progress" }
    data = JSON.parse(progress[:data])

    assert_equal "HELLO", data["data"]
  end

  def test_summary_event_contains_scores
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }
    @evaluators["scored-eval"] = test_evaluator(
      task: ->(input) { input.to_s.upcase },
      scorers: [scorer]
    )

    post_json "/eval", {
      name: "scored-eval",
      data: {data: [{input: "hello", expected: "HELLO"}]},
      experiment_name: "test-experiment",
      project_id: "proj-123",
      parent: {object_type: "playground_id", object_id: "pg-123"}
    }

    events = parse_sse_events(last_response.body)
    summary = events.find { |e| e[:event] == "summary" }
    data = JSON.parse(summary[:data])

    assert data.key?("scores"), "Summary should contain scores"
    assert data.key?("experiment_name"), "Summary should contain experiment_name"
  end

  def test_error_still_emits_progress_and_done
    @evaluators["failing-eval"] = test_evaluator(
      task: ->(_input) { raise "task exploded" }
    )

    post_json "/eval", {
      name: "failing-eval",
      data: {data: [{input: "hello"}]},
      experiment_name: "test-experiment",
      project_id: "proj-123",
      parent: {object_type: "playground_id", object_id: "pg-123"}
    }

    events = parse_sse_events(last_response.body)

    assert events.any? { |e| e[:event] == "progress" || e[:event] == "error" }
    assert_equal "done", events.last[:event]
  end

  def test_404_for_unknown_evaluator
    post_json "/eval", {
      name: "nonexistent",
      data: {data: [{input: "hello"}]},
      experiment_name: "test-experiment",
      project_id: "proj-123"
    }

    assert_equal 404, last_response.status
    body = JSON.parse(last_response.body)
    assert_match(/not found/i, body["error"])
  end

  def test_400_for_missing_data
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    post_json "/eval", {
      name: "test-eval",
      experiment_name: "test-experiment",
      project_id: "proj-123"
    }

    assert_equal 400, last_response.status
  end

  def test_400_for_multiple_data_specs
    @evaluators["test-eval"] = test_evaluator(task: ->(input) { input })

    post_json "/eval", {
      name: "test-eval",
      data: {
        data: [{input: "hello"}],
        dataset_name: "my-dataset"
      },
      experiment_name: "test-experiment",
      project_id: "proj-123"
    }

    assert_equal 400, last_response.status
  end

  def test_400_for_missing_name
    post_json "/eval", {
      data: {data: [{input: "hello"}]},
      experiment_name: "test-experiment",
      project_id: "proj-123"
    }

    assert_equal 400, last_response.status
  end

  def test_rejects_get
    get "/eval"
    assert_equal 405, last_response.status
  end

  private

  def test_evaluator(**kwargs)
    Test::Support::EvalHelper::TestEvaluator.new(tracer_provider: @rig.tracer_provider, **kwargs)
  end

  def post_json(path, body)
    post path, JSON.generate(body), {"CONTENT_TYPE" => "application/json"}
  end
end
