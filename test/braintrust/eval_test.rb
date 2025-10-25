# frozen_string_literal: true

require "test_helper"
require "braintrust/eval"

class Braintrust::EvalTest < Minitest::Test
  def test_eval_scorer_helper
    # Test Eval.scorer helper method
    scorer = Braintrust::Eval.scorer("test_scorer") do |input, expected, output|
      (output == expected) ? 1.0 : 0.0
    end

    assert_equal "test_scorer", scorer.name
    assert_instance_of Braintrust::Eval::Scorer, scorer
  end

  def test_eval_run_basic
    VCR.use_cassette("eval/run_basic") do
      state = get_non_global_state

      task = ->(input) { input.upcase }
      scorer = Braintrust::Eval.scorer("exact") do |input, expected, output|
        (output == expected) ? 1.0 : 0.0
      end

      result = Braintrust::Eval.run(
        project: "ruby-sdk-test",
        experiment: "test-ruby-sdk-basic",
        cases: [
          {input: "hello", expected: "HELLO"},
          {input: "world", expected: "WORLD"}
        ],
        task: task,
        scorers: [scorer],
        state: state,
        quiet: true
      )

      assert_instance_of Braintrust::Eval::Result, result
      assert result.success?
      assert_equal [], result.errors
      assert result.duration > 0
    end
  end

  def test_eval_run_with_task_error
    VCR.use_cassette("eval/run_task_error") do
      state = get_non_global_state

      task = ->(input) {
        raise "Task failed!" if input == "bad"
        input.upcase
      }

      scorer = Braintrust::Eval.scorer("exact") do |input, expected, output|
        (output == expected) ? 1.0 : 0.0
      end

      result = Braintrust::Eval.run(
        project: "ruby-sdk-test",
        experiment: "test-ruby-sdk-task-error",
        cases: [
          {input: "good", expected: "GOOD"},
          {input: "bad", expected: "BAD"}
        ],
        task: task,
        scorers: [scorer],
        state: state,
        quiet: true
      )

      assert result.failed?
      assert_equal 1, result.errors.length
      assert_match(/Task failed/, result.errors[0])
    end
  end

  def test_eval_run_with_scorer_error
    VCR.use_cassette("eval/run_scorer_error") do
      state = get_non_global_state

      task = ->(input) { input.upcase }

      scorer = Braintrust::Eval.scorer("failing_scorer") do |input, expected, output|
        raise "Scorer failed!" if input == "bad"
        1.0
      end

      result = Braintrust::Eval.run(
        project: "ruby-sdk-test",
        experiment: "test-ruby-sdk-scorer-error",
        cases: [
          {input: "good", expected: "GOOD"},
          {input: "bad", expected: "BAD"}
        ],
        task: task,
        scorers: [scorer],
        state: state,
        quiet: true
      )

      assert result.failed?
      assert_equal 1, result.errors.length
      assert_match(/Scorer.*failed/, result.errors[0])
    end
  end

  def test_eval_scorer_error_records_exception_event
    # Test that scorer errors are recorded as exception events on spans
    rig = setup_otel_test_rig

    task = ->(input) { input.upcase }
    good_scorer = Braintrust::Eval.scorer("good") { |i, e, o| 1.0 }
    failing_scorer = Braintrust::Eval.scorer("failing") do |i, e, o|
      raise "Intentional error" if i == "bad"
      1.0
    end

    # Use run_test_eval helper to avoid API calls in tests
    run_test_eval(
      experiment_id: "test-exp-123",
      experiment_name: "test-error-events",
      project_id: "test-proj-123",
      project_name: "test-project",
      cases: [{input: "bad", expected: "BAD"}],
      task: task,
      scorers: [good_scorer, failing_scorer],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    spans = rig.drain
    score_span = spans.find { |s| s.name == "score" }

    assert score_span, "Expected score span"
    assert score_span.events, "Expected span to have events"

    exception_event = score_span.events.find { |e| e.name == "exception" }
    assert exception_event, "Expected exception event"
    assert_equal "ScorerError", exception_event.attributes["exception.type"]
    assert_match(/Intentional error/, exception_event.attributes["exception.message"])
    assert exception_event.attributes["exception.stacktrace"], "Expected stacktrace in exception event"

    # Verify scores still recorded for successful scorers
    scores = JSON.parse(score_span.attributes["braintrust.scores"])
    assert_equal 1.0, scores["good"], "Good scorer should have succeeded"
    assert_nil scores["failing"], "Failing scorer should not have a score"
  end

  def test_eval_run_with_multiple_scorers
    VCR.use_cassette("eval/run_multiple_scorers") do
      state = get_non_global_state

      task = ->(input) { input.upcase }

      scorer1 = Braintrust::Eval.scorer("exact") do |input, expected, output|
        (output == expected) ? 1.0 : 0.0
      end

      scorer2 = Braintrust::Eval.scorer("length") do |input, expected, output|
        (output.length == expected.length) ? 1.0 : 0.0
      end

      result = Braintrust::Eval.run(
        project: "ruby-sdk-test",
        experiment: "test-ruby-sdk-multiple-scorers",
        cases: [
          {input: "hello", expected: "HELLO"}
        ],
        task: task,
        scorers: [scorer1, scorer2],
        state: state,
        quiet: true
      )

      assert result.success?
    end
  end

  def test_eval_run_with_callable_task
    VCR.use_cassette("eval/run_callable_task") do
      state = get_non_global_state

      callable_task = Class.new do
        def call(input)
          input.reverse
        end
      end.new

      scorer = Braintrust::Eval.scorer("exact") do |input, expected, output|
        (output == expected) ? 1.0 : 0.0
      end

      result = Braintrust::Eval.run(
        project: "ruby-sdk-test",
        experiment: "test-ruby-sdk-callable-task",
        cases: [
          {input: "hello", expected: "olleh"}
        ],
        task: callable_task,
        scorers: [scorer],
        state: state,
        quiet: true
      )

      assert result.success?
    end
  end

  def test_eval_run_validates_required_params
    # Test that run validates required parameters (no API call needed)
    error = assert_raises(ArgumentError) do
      Braintrust::Eval.run
      # Missing required params
    end

    # Ruby's keyword arg validation or our custom validation
    assert_match(/required|missing keyword/i, error.message)
  end

  def test_eval_run_validates_task_callable
    # Test that task must be callable (no API call needed)
    state = get_test_state

    error = assert_raises(ArgumentError) do
      Braintrust::Eval.run(
        project: "test",
        experiment: "test",
        cases: [],
        task: "not callable",  # String is not callable
        scorers: [],
        state: state
      )
    end

    assert_match(/task.*callable/i, error.message)
  end

  def test_eval_run_with_method_scorer
    VCR.use_cassette("eval/run_method_scorer") do
      state = get_non_global_state

      task = ->(input) { input.upcase }
      # Use a lambda instead of nested method
      test_method_scorer = ->(input, expected, output) { (output == expected) ? 1.0 : 0.0 }

      result = Braintrust::Eval.run(
        project: "ruby-sdk-test",
        experiment: "test-ruby-sdk-method-scorer",
        cases: [
          {input: "hello", expected: "HELLO"}
        ],
        task: task,
        scorers: [test_method_scorer],  # Pass lambda directly
        state: state,
        quiet: true
      )

      assert result.success?
    end
  end

  def test_eval_task_error_records_exception_on_task_span
    # Test that task errors are recorded as exception events on the TASK span (not eval span)
    rig = setup_otel_test_rig

    task = ->(input) {
      raise "Task intentionally failed" if input == "bad"
      input.upcase
    }
    scorer = Braintrust::Eval.scorer("good") { |i, e, o| 1.0 }

    # Use run_test_eval helper to avoid API calls in tests
    run_test_eval(
      experiment_id: "test-exp-123",
      experiment_name: "test-task-error",
      project_id: "test-proj-123",
      project_name: "test-project",
      cases: [{input: "bad", expected: "BAD"}],
      task: task,
      scorers: [scorer],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    spans = rig.drain
    task_span = spans.find { |s| s.name == "task" }
    eval_span = spans.find { |s| s.name == "eval" }

    # Task span should exist and have exception event (added by OpenTelemetry)
    assert task_span, "Expected task span"
    assert task_span.events, "Expected task span to have events"

    exception_event = task_span.events.find { |e| e.name == "exception" }
    assert exception_event, "Expected exception event on task span"
    assert_equal "RuntimeError", exception_event.attributes["exception.type"]
    assert_match(/Task intentionally failed/, exception_event.attributes["exception.message"])
    assert exception_event.attributes["exception.stacktrace"], "Expected stacktrace in exception event"

    # Eval span should also have error status
    assert eval_span, "Expected eval span"
    assert_equal OpenTelemetry::Trace::Status::ERROR, eval_span.status.code
  end

  def test_eval_run_with_tracing
    VCR.use_cassette("eval/run_with_tracing") do
      # Set up test rig for capturing spans (includes Braintrust processor)
      rig = setup_otel_test_rig

      # Initialize and login
      state = get_non_global_state

      task = ->(input) { input.upcase }
      scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

      result = Braintrust::Eval.run(
        project: "ruby-sdk-test",
        experiment: "test-ruby-sdk-tracing",
        cases: [{input: "hello", expected: "HELLO"}],
        task: task,
        scorers: [scorer],
        state: state,
        tracer_provider: rig.tracer_provider,
        quiet: true
      )

      assert result.success?

      # Verify spans were created
      spans = rig.drain

      # Should have: 1 eval span, 1 task span, 1 score span
      assert_equal 3, spans.length

      eval_span = spans.find { |s| s.name == "eval" }
      task_span = spans.find { |s| s.name == "task" }
      score_span = spans.find { |s| s.name == "score" }

      assert eval_span, "Expected eval span"
      assert task_span, "Expected task span"
      assert score_span, "Expected score span"

      # Verify eval span attributes
      assert eval_span.attributes["braintrust.parent"]
      assert_match(/experiment_id:[0-9a-f-]{36}/, eval_span.attributes["braintrust.parent"])
      assert_includes eval_span.attributes["braintrust.input_json"], "hello"
      assert_includes eval_span.attributes["braintrust.output_json"], "HELLO"

      # Verify task span
      assert task_span.attributes["braintrust.span_attributes"]
      assert_includes task_span.attributes["braintrust.span_attributes"], "task"

      # Verify score span
      assert score_span.attributes["braintrust.scores"]
      assert_includes score_span.attributes["braintrust.scores"], "exact"

      # Verify experiment result has permalink in correct format
      assert result.permalink.include?("object_type=experiment"), "Result permalink should be experiment URL"
      assert result.permalink.include?("object_id="), "Result permalink should have experiment ID"

      # Verify eval span has correct parent for experiment
      parent_attr = eval_span.attributes["braintrust.parent"]
      assert parent_attr.start_with?("experiment_id:"), "Eval span should have experiment_id parent"
    end
  end

  # Test dataset integration: dataset as string (same project as experiment)
  def test_eval_run_with_dataset_string
    VCR.use_cassette("eval/dataset_string") do
      state = get_non_global_state
      api = Braintrust::API.new(state: state)

      # Create a test dataset with records
      project_name = "ruby-sdk-test"
      dataset_name = "test-ruby-sdk-dataset-string"

      # Create dataset
      result = api.datasets.create(
        name: dataset_name,
        project_name: project_name,
        description: "Test dataset for eval integration"
      )
      dataset_id = result["dataset"]["id"]

      # Insert test records
      api.datasets.insert(
        id: dataset_id,
        events: [
          {input: "hello", expected: "HELLO"},
          {input: "world", expected: "WORLD"}
        ]
      )

      # Run eval with dataset as string (should use same project)
      task = ->(input) { input.upcase }
      scorer = Braintrust::Eval.scorer("exact") do |input, expected, output|
        (output == expected) ? 1.0 : 0.0
      end

      eval_result = Braintrust::Eval.run(
        project: project_name,
        experiment: "test-ruby-sdk-exp-dataset-string",
        dataset: dataset_name,  # String - should fetch from same project
        task: task,
        scorers: [scorer],
        state: state,
        quiet: true
      )

      assert_instance_of Braintrust::Eval::Result, eval_result
      assert eval_result.success?
      assert_equal [], eval_result.errors
      assert eval_result.duration > 0
    end
  end

  # Test dataset integration: dataset as hash with name + project
  def test_eval_run_with_dataset_hash_name_project
    VCR.use_cassette("eval/dataset_hash_name_project") do
      state = get_non_global_state
      api = Braintrust::API.new(state: state)

      # Create a test dataset
      project_name = "ruby-sdk-test"
      dataset_name = "test-ruby-sdk-dataset-hash"

      result = api.datasets.create(
        name: dataset_name,
        project_name: project_name
      )
      dataset_id = result["dataset"]["id"]

      # Insert test records
      api.datasets.insert(
        id: dataset_id,
        events: [{input: "test", expected: "TEST"}]
      )

      # Run eval with dataset as hash with explicit name + project
      task = ->(input) { input.upcase }
      scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

      eval_result = Braintrust::Eval.run(
        project: project_name,
        experiment: "test-ruby-sdk-exp-hash",
        dataset: {name: dataset_name, project: project_name},
        task: task,
        scorers: [scorer],
        state: state,
        quiet: true
      )

      assert eval_result.success?
    end
  end

  # Test dataset integration: dataset as hash with id
  def test_eval_run_with_dataset_hash_id
    VCR.use_cassette("eval/dataset_hash_id") do
      state = get_non_global_state
      api = Braintrust::API.new(state: state)

      # Create a test dataset
      project_name = "ruby-sdk-test"
      dataset_name = "test-ruby-sdk-dataset-id"

      result = api.datasets.create(
        name: dataset_name,
        project_name: project_name
      )
      dataset_id = result["dataset"]["id"]

      # Insert test records
      api.datasets.insert(
        id: dataset_id,
        events: [{input: "test", expected: "TEST"}]
      )

      # Run eval with dataset as hash with id
      task = ->(input) { input.upcase }
      scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

      eval_result = Braintrust::Eval.run(
        project: project_name,
        experiment: "test-ruby-sdk-exp-id",
        dataset: {id: dataset_id},  # By ID only
        task: task,
        scorers: [scorer],
        state: state,
        quiet: true
      )

      assert eval_result.success?
    end
  end

  # Test dataset integration: dataset with limit option
  def test_eval_run_with_dataset_limit
    VCR.use_cassette("eval/dataset_limit") do
      state = get_non_global_state
      api = Braintrust::API.new(state: state)

      # Create a test dataset with multiple records
      project_name = "ruby-sdk-test"
      dataset_name = "test-ruby-sdk-dataset-limit"

      result = api.datasets.create(
        name: dataset_name,
        project_name: project_name
      )
      dataset_id = result["dataset"]["id"]

      # Insert 5 test records
      api.datasets.insert(
        id: dataset_id,
        events: [
          {input: "one", expected: "ONE"},
          {input: "two", expected: "TWO"},
          {input: "three", expected: "THREE"},
          {input: "four", expected: "FOUR"},
          {input: "five", expected: "FIVE"}
        ]
      )

      # Track how many cases were executed
      executed_count = 0
      task = ->(input) {
        executed_count += 1
        input.upcase
      }
      scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

      # Run eval with limit of 2
      eval_result = Braintrust::Eval.run(
        project: project_name,
        experiment: "test-ruby-sdk-exp-limit",
        dataset: {name: dataset_name, project: project_name, limit: 2},
        task: task,
        scorers: [scorer],
        state: state,
        quiet: true
      )

      assert eval_result.success?
      assert_equal 2, executed_count, "Should have executed exactly 2 cases"
    end
  end

  # Test dataset integration: error when both dataset and cases provided
  def test_eval_run_with_both_dataset_and_cases_errors
    VCR.use_cassette("eval/run_both_dataset_and_cases_error") do
      state = get_non_global_state

      task = ->(input) { input.upcase }
      scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

      # Try to provide both dataset and cases - should raise error
      error = assert_raises(ArgumentError) do
        Braintrust::Eval.run(
          project: "ruby-sdk-test",
          experiment: "test-error",
          dataset: "some-dataset",
          cases: [{input: "test"}],
          task: task,
          scorers: [scorer],
          state: state
        )
      end

      assert_match(/mutually exclusive/i, error.message)
    end
  end
end
