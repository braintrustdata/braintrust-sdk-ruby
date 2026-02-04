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
      api = get_integration_test_api

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
        api: api,
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
      api = get_integration_test_api

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
        api: api,
        quiet: true
      )

      assert result.failed?
      assert_equal 1, result.errors.length
      assert_match(/Task failed/, result.errors[0])
    end
  end

  def test_eval_run_with_scorer_error
    VCR.use_cassette("eval/run_scorer_error") do
      api = get_integration_test_api

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
        api: api,
        quiet: true
      )

      assert result.failed?
      assert_equal 1, result.errors.length
      assert_match(/Scorers failed/, result.errors[0])
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
      api: rig.api,
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
      api = get_integration_test_api

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
        api: api,
        quiet: true
      )

      assert result.success?
    end
  end

  def test_eval_run_with_callable_task
    VCR.use_cassette("eval/run_callable_task") do
      api = get_integration_test_api

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
        api: api,
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
    # Note: Validation happens before API is used, so we can pass nil
    error = assert_raises(ArgumentError) do
      Braintrust::Eval.run(
        project: "test",
        experiment: "test",
        cases: [],
        task: "not callable",  # String is not callable
        scorers: []
      )
    end

    assert_match(/task.*callable/i, error.message)
  end

  def test_eval_run_with_method_scorer
    VCR.use_cassette("eval/run_method_scorer") do
      api = get_integration_test_api

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
        api: api,
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
      api: rig.api,
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
      api = get_integration_test_api

      task = ->(input) { input.upcase }
      scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

      result = Braintrust::Eval.run(
        project: "ruby-sdk-test",
        experiment: "test-ruby-sdk-tracing",
        cases: [{input: "hello", expected: "HELLO"}],
        task: task,
        scorers: [scorer],
        api: api,
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
      api = get_integration_test_api

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
        api: api,
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
      api = get_integration_test_api

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
        api: api,
        quiet: true
      )

      assert eval_result.success?
    end
  end

  # Test dataset integration: dataset as hash with id
  def test_eval_run_with_dataset_hash_id
    VCR.use_cassette("eval/dataset_hash_id") do
      api = get_integration_test_api

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
        api: api,
        quiet: true
      )

      assert eval_result.success?
    end
  end

  # Test dataset integration: dataset with limit option
  def test_eval_run_with_dataset_limit
    VCR.use_cassette("eval/dataset_limit") do
      api = get_integration_test_api

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
        api: api,
        quiet: true
      )

      assert eval_result.success?
      assert_equal 2, executed_count, "Should have executed exactly 2 cases"
    end
  end

  # Test dataset integration: error when both dataset and cases provided
  def test_eval_run_with_both_dataset_and_cases_errors
    VCR.use_cassette("eval/run_both_dataset_and_cases_error") do
      api = get_integration_test_api

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
          api: api
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
      api: rig.api,
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
      api: rig.api,
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
      api: rig.api,
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
        api: rig.api,
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
      api: rig.api,
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
      api: rig.api,
      tracer_provider: rig.tracer_provider
    )
    assert result.success?
    assert_equal %w[a b], order
  end

  # ============================================
  # Origin tests (for remote dataset linking)
  # ============================================
  # Origin is automatically generated when using remote datasets.
  # It links eval spans back to their source dataset records in the UI.

  def test_runner_does_not_set_origin_when_case_has_no_origin
    # Inline cases (not from remote datasets) have no origin
    rig = setup_otel_test_rig

    task = ->(input) { input.upcase }
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

    run_test_eval(
      experiment_id: "test-exp-123",
      experiment_name: "test-no-origin",
      project_id: "test-proj-123",
      project_name: "test-project",
      cases: [{input: "hello", expected: "HELLO"}],
      task: task,
      scorers: [scorer],
      api: rig.api,
      tracer_provider: rig.tracer_provider
    )

    spans = rig.drain
    eval_span = spans.find { |s| s.name == "eval" }

    assert eval_span, "Expected eval span"
    assert_nil eval_span.attributes["braintrust.origin"]
  end

  # Integration test: verify real API dataset records result in correct origin on spans
  # Note: Dataset is not deleted after test - relies on idempotent create (same pattern as other dataset tests)
  def test_eval_with_remote_dataset_sets_origin_from_api_response
    VCR.use_cassette("eval/dataset_origin") do
      # Set up span capture (uses unit test state internally, but we override state for API calls)
      rig = setup_otel_test_rig
      # Get integration API for real API calls via VCR
      api = get_integration_test_api

      # Create/reuse test dataset (idempotent)
      project_name = "ruby-sdk-test"
      dataset_name = "test-ruby-sdk-dataset-origin"

      result = api.datasets.create(
        name: dataset_name,
        project_name: project_name,
        description: "Test dataset for origin integration"
      )
      dataset_id = result["dataset"]["id"]

      # Insert test record
      api.datasets.insert(
        id: dataset_id,
        events: [{input: "origin-test", expected: "ORIGIN-TEST"}]
      )

      # Run eval with remote dataset
      task = ->(input) { input.upcase }
      scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }

      eval_result = Braintrust::Eval.run(
        project: project_name,
        experiment: "test-ruby-sdk-exp-origin",
        dataset: dataset_name,
        task: task,
        scorers: [scorer],
        api: api,
        tracer_provider: rig.tracer_provider,
        quiet: true
      )

      assert eval_result.success?

      # Verify origin was set on eval spans
      spans = rig.drain
      eval_spans = spans.select { |s| s.name == "eval" }
      assert eval_spans.any?, "Expected at least one eval span"

      # All eval spans from a dataset should have origin
      eval_spans.each do |span|
        origin_json = span.attributes["braintrust.origin"]
        assert origin_json, "Expected braintrust.origin on eval span"

        # Verify origin structure matches expected format
        origin = JSON.parse(origin_json)
        assert_equal "dataset", origin["object_type"]
        assert origin["object_id"], "origin.object_id should be present"
        assert origin["id"], "origin.id (record id) should be present"
        assert origin["_xact_id"], "origin._xact_id should be present"
      end
    end
  end
end
