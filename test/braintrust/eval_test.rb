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
      state = get_integration_test_state

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
      state = get_integration_test_state

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
      state = get_integration_test_state

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
      state = get_integration_test_state

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
      state = get_integration_test_state

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
    state = get_unit_test_state

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
      state = get_integration_test_state

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
      state = get_integration_test_state

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
      state = get_integration_test_state
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
      state = get_integration_test_state
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
      state = get_integration_test_state
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
      state = get_integration_test_state
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
      state = get_integration_test_state

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

  # ============================================
  # Parallelism tests
  # ============================================

  def test_eval_run_with_parallelism_executes_all_cases
    rig = setup_otel_test_rig

    executed = Queue.new
    task = ->(input) {
      executed << input
      input.upcase
    }
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

    result = run_test_eval(
      experiment_id: "test-exp-123",
      experiment_name: "test-parallel",
      project_id: "test-proj-123",
      project_name: "test-project",
      cases: [
        {input: "a", expected: "A"},
        {input: "b", expected: "B"},
        {input: "c", expected: "C"},
        {input: "d", expected: "D"}
      ],
      task: task,
      scorers: [scorer],
      parallelism: 3,
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    assert result.success?
    assert_equal 4, executed.size

    # Verify all inputs were processed
    executed_inputs = [].tap { |a| a << executed.pop until executed.empty? }
    assert_equal %w[a b c d].sort, executed_inputs.sort
  end

  def test_eval_run_parallelism_1_matches_sequential
    rig = setup_otel_test_rig

    order = []
    mutex = Mutex.new
    task = ->(input) {
      mutex.synchronize { order << input }
      input.upcase
    }
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

    result = run_test_eval(
      experiment_id: "test-exp-123",
      experiment_name: "test-sequential",
      project_id: "test-proj-123",
      project_name: "test-project",
      cases: [
        {input: "a", expected: "A"},
        {input: "b", expected: "B"},
        {input: "c", expected: "C"}
      ],
      task: task,
      scorers: [scorer],
      parallelism: 1,
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    assert result.success?
    # With parallelism 1, order should be preserved
    assert_equal %w[a b c], order
  end

  def test_eval_run_parallel_collects_errors_from_threads
    rig = setup_otel_test_rig

    task = ->(input) {
      raise "intentional failure" if input == "bad"
      input.upcase
    }
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

    result = run_test_eval(
      experiment_id: "test-exp-123",
      experiment_name: "test-parallel-errors",
      project_id: "test-proj-123",
      project_name: "test-project",
      cases: [
        {input: "good1", expected: "GOOD1"},
        {input: "bad", expected: "BAD"},
        {input: "good2", expected: "GOOD2"}
      ],
      task: task,
      scorers: [scorer],
      parallelism: 3,
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    assert result.failed?
    assert_equal 1, result.errors.length
    assert_match(/intentional failure/, result.errors.first)
  end

  def test_eval_run_parallelism_exceeds_max_raises
    rig = setup_otel_test_rig

    task = ->(input) { input.upcase }
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

    max_parallelism = Braintrust::Eval::Runner::MAX_PARALLELISM
    error = assert_raises(ArgumentError) do
      run_test_eval(
        experiment_id: "test-exp-123",
        experiment_name: "test-invalid",
        project_id: "test-proj-123",
        project_name: "test-project",
        cases: [{input: "test", expected: "TEST"}],
        task: task,
        scorers: [scorer],
        parallelism: max_parallelism + 1,
        state: rig.state,
        tracer_provider: rig.tracer_provider
      )
    end
    assert_match(/cannot exceed #{max_parallelism}/, error.message)
  end

  def test_eval_run_invalid_parallelism_falls_back_to_sequential
    rig = setup_otel_test_rig

    order = []
    mutex = Mutex.new
    task = ->(input) {
      mutex.synchronize { order << input }
      input.upcase
    }
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

    # Test parallelism: 0 falls back to sequential
    order.clear
    result = run_test_eval(
      experiment_id: "test-exp-123",
      experiment_name: "test-fallback",
      project_id: "test-proj-123",
      project_name: "test-project",
      cases: [
        {input: "a", expected: "A"},
        {input: "b", expected: "B"}
      ],
      task: task,
      scorers: [scorer],
      parallelism: 0,
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    assert result.success?
    assert_equal %w[a b], order

    # Test parallelism: -1 falls back to sequential
    order.clear
    result = run_test_eval(
      experiment_id: "test-exp-123",
      experiment_name: "test-fallback",
      project_id: "test-proj-123",
      project_name: "test-project",
      cases: [
        {input: "a", expected: "A"},
        {input: "b", expected: "B"}
      ],
      task: task,
      scorers: [scorer],
      parallelism: -1,
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    assert result.success?
    assert_equal %w[a b], order
  end
end

# Unit tests for Eval::Runner class
class Braintrust::Eval::RunnerTest < Minitest::Test
  # Define a method-based scorer for tests
  def exact_match_scorer(input, expected, output, metadata = {})
    (output == expected) ? 1.0 : 0.0
  end

  # ============================================
  # Runner#run tests - basic functionality
  # ============================================

  def test_runner_run_returns_result_object
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input.upcase },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    result = runner.run([{input: "hello", expected: "HELLO"}])

    assert_instance_of Braintrust::Eval::Result, result
  end

  def test_runner_run_populates_result_fields
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input.upcase },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    result = runner.run([{input: "hello", expected: "HELLO"}])

    assert_equal "exp-123", result.experiment_id
    assert_equal "test-experiment", result.experiment_name
    assert_equal "proj-456", result.project_id
    assert_equal "test-project", result.project_name
    assert result.duration > 0
    assert_empty result.errors
    assert result.success?
  end

  def test_runner_run_generates_correct_permalink
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-abc-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input },
      scorers: [Braintrust::Eval.scorer("test") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    result = runner.run([{input: "test"}])

    expected_permalink = "#{rig.state.app_url}/app/#{rig.state.org_name}/object?object_type=experiment&object_id=exp-abc-123"
    assert_equal expected_permalink, result.permalink
  end

  def test_runner_run_executes_task_for_each_case
    rig = setup_otel_test_rig
    executed_inputs = []

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) {
        executed_inputs << input
        input.upcase
      },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    runner.run([
      {input: "a", expected: "A"},
      {input: "b", expected: "B"},
      {input: "c", expected: "C"}
    ])

    assert_equal %w[a b c], executed_inputs
  end

  def test_runner_run_executes_scorers_with_correct_args
    rig = setup_otel_test_rig
    scorer_calls = []

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input.upcase },
      scorers: [
        Braintrust::Eval.scorer("recorder") { |input, expected, output, metadata|
          scorer_calls << {input: input, expected: expected, output: output, metadata: metadata}
          1.0
        }
      ],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    runner.run([
      {input: "hello", expected: "HELLO", metadata: {key: "value"}}
    ])

    assert_equal 1, scorer_calls.length
    assert_equal "hello", scorer_calls[0][:input]
    assert_equal "HELLO", scorer_calls[0][:expected]
    assert_equal "HELLO", scorer_calls[0][:output]
    assert_equal({key: "value"}, scorer_calls[0][:metadata])
  end

  # ============================================
  # Runner#run tests - cases normalization
  # ============================================

  def test_runner_run_accepts_array_of_hashes
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input },
      scorers: [Braintrust::Eval.scorer("test") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    result = runner.run([{input: "a"}, {input: "b"}])
    assert result.success?
  end

  def test_runner_run_accepts_cases_object
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input },
      scorers: [Braintrust::Eval.scorer("test") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    cases = Braintrust::Eval::Cases.new([{input: "test"}])
    result = runner.run(cases)
    assert result.success?
  end

  def test_runner_run_accepts_enumerable
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input },
      scorers: [Braintrust::Eval.scorer("test") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    # Use an Enumerator
    enum = [{input: "a"}, {input: "b"}].each
    result = runner.run(enum)
    assert result.success?
  end

  # ============================================
  # Runner#run tests - error handling
  # ============================================

  def test_runner_run_collects_task_errors
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) {
        raise "Task error!" if input == "bad"
        input.upcase
      },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    result = runner.run([
      {input: "good", expected: "GOOD"},
      {input: "bad", expected: "BAD"}
    ])

    assert result.failed?
    assert_equal 1, result.errors.length
    assert_match(/Task failed for input 'bad'/, result.errors[0])
    assert_match(/Task error!/, result.errors[0])
  end

  def test_runner_run_collects_scorer_errors
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input.upcase },
      scorers: [
        Braintrust::Eval.scorer("failing") { |i, e, o|
          raise "Scorer error!" if i == "bad"
          1.0
        }
      ],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    result = runner.run([
      {input: "good", expected: "GOOD"},
      {input: "bad", expected: "BAD"}
    ])

    assert result.failed?
    assert_equal 1, result.errors.length
    assert_match(/Scorers failed for input 'bad'/, result.errors[0])
  end

  def test_runner_run_continues_after_task_error
    rig = setup_otel_test_rig
    executed = []

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) {
        executed << input
        raise "Error!" if input == "b"
        input.upcase
      },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    result = runner.run([
      {input: "a"},
      {input: "b"},
      {input: "c"}
    ])

    # All cases should be executed despite error on "b"
    assert_equal %w[a b c], executed
    assert_equal 1, result.errors.length
  end

  def test_runner_run_collects_multiple_errors
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) {
        raise "Error for #{input}" if input.start_with?("bad")
        input.upcase
      },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    result = runner.run([
      {input: "good"},
      {input: "bad1"},
      {input: "bad2"}
    ])

    assert result.failed?
    assert_equal 2, result.errors.length
  end

  # ============================================
  # Runner#run tests - parallelism
  # ============================================

  def test_runner_run_with_parallelism_greater_than_1
    rig = setup_otel_test_rig
    executed = Queue.new

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) {
        executed << input
        input.upcase
      },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    result = runner.run([
      {input: "a"},
      {input: "b"},
      {input: "c"},
      {input: "d"}
    ], parallelism: 3)

    assert result.success?
    assert_equal 4, executed.size
  end

  def test_runner_run_sequential_preserves_order
    rig = setup_otel_test_rig
    order = []

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) {
        order << input
        input.upcase
      },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    runner.run([
      {input: "a"},
      {input: "b"},
      {input: "c"}
    ], parallelism: 1)

    assert_equal %w[a b c], order
  end

  def test_runner_run_default_parallelism_is_sequential
    rig = setup_otel_test_rig
    order = []

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) {
        order << input
        input.upcase
      },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    # Don't pass parallelism, should default to 1 (sequential)
    runner.run([{input: "a"}, {input: "b"}, {input: "c"}])

    assert_equal %w[a b c], order
  end

  # ============================================
  # Runner#run tests - OpenTelemetry spans
  # ============================================

  def test_runner_run_creates_eval_spans
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input.upcase },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    runner.run([{input: "hello", expected: "HELLO"}])

    spans = rig.exporter.finished_spans
    eval_spans = spans.select { |s| s.name == "eval" }

    assert_equal 1, eval_spans.length
    assert_equal "experiment_id:exp-123", eval_spans[0].attributes["braintrust.parent"]
  end

  def test_runner_run_creates_task_spans
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input.upcase },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    runner.run([{input: "hello", expected: "HELLO"}])

    spans = rig.exporter.finished_spans
    task_spans = spans.select { |s| s.name == "task" }

    assert_equal 1, task_spans.length
    assert_equal "experiment_id:exp-123", task_spans[0].attributes["braintrust.parent"]
  end

  def test_runner_run_creates_score_spans
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input.upcase },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    runner.run([{input: "hello", expected: "HELLO"}])

    spans = rig.exporter.finished_spans
    score_spans = spans.select { |s| s.name == "score" }

    assert_equal 1, score_spans.length
    assert_equal "experiment_id:exp-123", score_spans[0].attributes["braintrust.parent"]
  end

  def test_runner_run_records_scores_on_span
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) { input.upcase },
      scorers: [
        Braintrust::Eval.scorer("accuracy") { |i, e, o| 0.95 },
        Braintrust::Eval.scorer("relevance") { |i, e, o| 0.87 }
      ],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    runner.run([{input: "hello", expected: "HELLO"}])

    spans = rig.exporter.finished_spans
    score_span = spans.find { |s| s.name == "score" }

    scores = JSON.parse(score_span.attributes["braintrust.scores"])
    assert_equal 0.95, scores["accuracy"]
    assert_equal 0.87, scores["relevance"]
  end

  # ============================================
  # Runner reusability tests
  # ============================================

  def test_runner_can_be_run_multiple_times
    rig = setup_otel_test_rig
    call_count = 0

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) {
        call_count += 1
        input.upcase
      },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    result1 = runner.run([{input: "a"}])
    result2 = runner.run([{input: "b"}, {input: "c"}])

    assert result1.success?
    assert result2.success?
    assert_equal 3, call_count
  end

  def test_runner_runs_are_independent
    rig = setup_otel_test_rig

    runner = Braintrust::Eval::Runner.new(
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      task: ->(input) {
        raise "Error!" if input == "bad"
        input.upcase
      },
      scorers: [Braintrust::Eval.scorer("exact") { |i, e, o| 1.0 }],
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )

    # First run has an error
    result1 = runner.run([{input: "bad"}])
    assert result1.failed?

    # Second run should be independent (no errors from first run)
    result2 = runner.run([{input: "good"}])
    assert result2.success?
    assert_empty result2.errors
  end
end
