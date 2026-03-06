# frozen_string_literal: true

require "test_helper"
require "braintrust/eval"

# Unit tests for Eval::Runner class
class Braintrust::Eval::RunnerTest < Minitest::Test
  # ============================================
  # Runner#run tests - basic functionality
  # ============================================

  def test_runner_run_returns_result_object
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { |expected:, output:| (output == expected) ? 1.0 : 0.0 }],
      cases: [{input: "hello", expected: "HELLO"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    assert_instance_of Braintrust::Eval::Result, result
  end

  def test_runner_run_populates_result_fields
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "hello", expected: "HELLO"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    assert_equal "exp-123", result.experiment_id
    assert_equal "test-experiment", result.experiment_name
    assert_equal "proj-456", result.project_id
    assert_equal "test-project", result.project_name
    assert result.duration > 0
    assert_empty result.errors
    assert result.success?

    # Check scores is populated
    assert_equal({"exact" => [1.0]}, result.scores)
  end

  def test_runner_run_generates_correct_permalink
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input },
      scorers: [Braintrust::Scorer.new("test") { 1.0 }],
      cases: [{input: "test"}],
      experiment_id: "exp-abc-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    expected_permalink = "#{rig.state.app_url}/app/#{rig.state.org_name}/object?object_type=experiment&object_id=exp-abc-123"
    assert_equal expected_permalink, result.permalink
  end

  def test_runner_run_executes_task_for_each_case
    rig = setup_otel_test_rig
    executed_inputs = []

    context = Braintrust::Eval::Context.build(
      task: ->(input:) {
        executed_inputs << input
        input.upcase
      },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [
        {input: "a", expected: "A"},
        {input: "b", expected: "B"},
        {input: "c", expected: "C"}
      ],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    assert_equal %w[a b c], executed_inputs

    # Check scores contains all scores
    assert_equal({"exact" => [1.0, 1.0, 1.0]}, result.scores)
  end

  def test_runner_scorer_with_subset_kwargs_works_end_to_end
    rig = setup_otel_test_rig

    # Scorer declares only output: — no **, no input:, no expected:, no metadata:, no tags:
    scorer = Braintrust::Scorer.new("output_only") { |output:| (output == "HELLO") ? 1.0 : 0.0 }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello", expected: "HELLO", metadata: {key: "val"}, tags: ["tag1"]}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    assert result.success?
    assert_equal({"output_only" => [1.0]}, result.scores)
  end

  def test_runner_task_with_subset_kwargs_works_end_to_end
    rig = setup_otel_test_rig

    # Task declares only input: — Runner also passes metadata: and tags:
    context = Braintrust::Eval::Context.build(
      task: Braintrust::Task.new("input_only") { |input:| input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { |output:, expected:| (output == expected) ? 1.0 : 0.0 }],
      cases: [{input: "hello", expected: "HELLO", metadata: {key: "val"}, tags: ["tag1"]}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    assert result.success?
    assert_equal({"exact" => [1.0]}, result.scores)
  end

  def test_runner_run_executes_scorers_with_correct_args
    rig = setup_otel_test_rig
    scorer_calls = []

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [
        Braintrust::Scorer.new("recorder") { |input:, expected:, output:, metadata:|
          scorer_calls << {input: input, expected: expected, output: output, metadata: metadata}
          1.0
        }
      ],
      cases: [
        {input: "hello", expected: "HELLO", metadata: {key: "value"}}
      ],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    runner.run

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

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input },
      scorers: [Braintrust::Scorer.new("test") { 1.0 }],
      cases: [{input: "a"}, {input: "b"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run
    assert result.success?
  end

  def test_runner_run_accepts_cases_object
    rig = setup_otel_test_rig

    cases = Braintrust::Eval::Cases.new([{input: "test"}])
    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input },
      scorers: [Braintrust::Scorer.new("test") { 1.0 }],
      cases: cases,
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run
    assert result.success?
  end

  def test_runner_run_accepts_enumerable
    rig = setup_otel_test_rig

    # Use an Enumerator
    enum = [{input: "a"}, {input: "b"}].each
    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input },
      scorers: [Braintrust::Scorer.new("test") { 1.0 }],
      cases: enum,
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run
    assert result.success?
  end

  # ============================================
  # Runner#run tests - error handling
  # ============================================

  def test_runner_run_collects_task_errors
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) {
        raise "Task error!" if input == "bad"
        input.upcase
      },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [
        {input: "good", expected: "GOOD"},
        {input: "bad", expected: "BAD"}
      ],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    assert result.failed?
    assert_equal 1, result.errors.length
    assert_match(/Task failed for input 'bad'/, result.errors[0])
    assert_match(/Task error!/, result.errors[0])
  end

  def test_runner_run_collects_scorer_errors
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [
        Braintrust::Scorer.new("failing") { |input:|
          raise "Scorer error!" if input == "bad"
          1.0
        }
      ],
      cases: [
        {input: "good", expected: "GOOD"},
        {input: "bad", expected: "BAD"}
      ],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    assert result.failed?
    assert_equal 1, result.errors.length
    assert_match(/Scorers failed for input 'bad'/, result.errors[0])
  end

  def test_runner_run_continues_after_task_error
    rig = setup_otel_test_rig
    executed = []

    context = Braintrust::Eval::Context.build(
      task: ->(input:) {
        executed << input
        raise "Error!" if input == "b"
        input.upcase
      },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [
        {input: "a"},
        {input: "b"},
        {input: "c"}
      ],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    # All cases should be executed despite error on "b"
    assert_equal %w[a b c], executed
    assert_equal 1, result.errors.length
  end

  def test_runner_run_collects_multiple_errors
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) {
        raise "Error for #{input}" if input.start_with?("bad")
        input.upcase
      },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [
        {input: "good"},
        {input: "bad1"},
        {input: "bad2"}
      ],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    assert result.failed?
    assert_equal 2, result.errors.length
  end

  # ============================================
  # Runner#run tests - parallelism
  # ============================================

  def test_runner_run_with_parallelism_greater_than_1
    rig = setup_otel_test_rig
    executed = Queue.new

    context = Braintrust::Eval::Context.build(
      task: ->(input:) {
        executed << input
        input.upcase
      },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [
        {input: "a"},
        {input: "b"},
        {input: "c"},
        {input: "d"}
      ],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run(parallelism: 3)

    assert result.success?
    assert_equal 4, executed.size
  end

  def test_runner_run_sequential_preserves_order
    rig = setup_otel_test_rig
    order = []

    context = Braintrust::Eval::Context.build(
      task: ->(input:) {
        order << input
        input.upcase
      },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [
        {input: "a"},
        {input: "b"},
        {input: "c"}
      ],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    runner.run(parallelism: 1)

    assert_equal %w[a b c], order
  end

  def test_runner_run_default_parallelism_is_sequential
    rig = setup_otel_test_rig
    order = []

    context = Braintrust::Eval::Context.build(
      task: ->(input:) {
        order << input
        input.upcase
      },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "a"}, {input: "b"}, {input: "c"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    # Don't pass parallelism, should default to 1 (sequential)
    runner.run

    assert_equal %w[a b c], order
  end

  # ============================================
  # Runner#run tests - OpenTelemetry spans
  # ============================================

  def test_runner_run_creates_eval_spans
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "hello", expected: "HELLO"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider,
      parent: {object_type: "experiment_id", object_id: "exp-123"}
    )
    runner = Braintrust::Eval::Runner.new(context)

    runner.run

    spans = rig.exporter.finished_spans
    eval_spans = spans.select { |s| s.name == "eval" }

    assert_equal 1, eval_spans.length
    assert_equal "experiment_id:exp-123", eval_spans[0].attributes["braintrust.parent"]
  end

  def test_runner_run_creates_task_spans
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "hello", expected: "HELLO"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider,
      parent: {object_type: "experiment_id", object_id: "exp-123"}
    )
    runner = Braintrust::Eval::Runner.new(context)

    runner.run

    spans = rig.exporter.finished_spans
    task_spans = spans.select { |s| s.name == "task" }

    assert_equal 1, task_spans.length
    assert_equal "experiment_id:exp-123", task_spans[0].attributes["braintrust.parent"]
  end

  def test_runner_run_creates_score_spans
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "hello", expected: "HELLO"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider,
      parent: {object_type: "experiment_id", object_id: "exp-123"}
    )
    runner = Braintrust::Eval::Runner.new(context)

    runner.run

    spans = rig.exporter.finished_spans
    score_spans = spans.select { |s| s.name == "score" }

    assert_equal 1, score_spans.length
    assert_equal "experiment_id:exp-123", score_spans[0].attributes["braintrust.parent"]
  end

  def test_runner_run_records_scores_on_span
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [
        Braintrust::Scorer.new("accuracy") { 0.95 },
        Braintrust::Scorer.new("relevance") { 0.87 }
      ],
      cases: [{input: "hello", expected: "HELLO"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    result = runner.run

    spans = rig.exporter.finished_spans
    score_span = spans.find { |s| s.name == "score" }

    scores = JSON.parse(score_span.attributes["braintrust.scores"])
    assert_equal 0.95, scores["accuracy"]
    assert_equal 0.87, scores["relevance"]

    # Check scores contains scores from multiple scorers
    assert_equal({"accuracy" => [0.95], "relevance" => [0.87]}, result.scores)
  end

  # ============================================
  # Runner reusability tests
  # ============================================

  def test_runner_can_be_run_multiple_times
    rig = setup_otel_test_rig
    call_count = 0

    task = ->(input:) {
      call_count += 1
      input.upcase
    }
    scorer = Braintrust::Scorer.new("exact") { 1.0 }

    context1 = Braintrust::Eval::Context.build(
      task: task,
      scorers: [scorer],
      cases: [{input: "a"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner1 = Braintrust::Eval::Runner.new(context1)
    result1 = runner1.run

    context2 = Braintrust::Eval::Context.build(
      task: task,
      scorers: [scorer],
      cases: [{input: "b"}, {input: "c"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner2 = Braintrust::Eval::Runner.new(context2)
    result2 = runner2.run

    assert result1.success?
    assert result2.success?
    assert_equal 3, call_count
  end

  def test_runner_runs_are_independent
    rig = setup_otel_test_rig

    task = ->(input:) {
      raise "Error!" if input == "bad"
      input.upcase
    }
    scorer = Braintrust::Scorer.new("exact") { 1.0 }

    # First run has an error
    context1 = Braintrust::Eval::Context.build(
      task: task,
      scorers: [scorer],
      cases: [{input: "bad"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner1 = Braintrust::Eval::Runner.new(context1)
    result1 = runner1.run
    assert result1.failed?

    # Second run should be independent (no errors from first run)
    context2 = Braintrust::Eval::Context.build(
      task: task,
      scorers: [scorer],
      cases: [{input: "good"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner2 = Braintrust::Eval::Runner.new(context2)
    result2 = runner2.run
    assert result2.success?
    assert_empty result2.errors
  end

  def test_runner_scores_is_reset_between_runs
    rig = setup_otel_test_rig

    task = ->(input:) { input.upcase }
    scorer = Braintrust::Scorer.new("exact") { |expected:, output:| (output == expected) ? 1.0 : 0.0 }

    # First run with 2 cases
    context1 = Braintrust::Eval::Context.build(
      task: task,
      scorers: [scorer],
      cases: [
        {input: "a", expected: "A"},
        {input: "b", expected: "B"}
      ],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner1 = Braintrust::Eval::Runner.new(context1)
    result1 = runner1.run
    assert_equal({"exact" => [1.0, 1.0]}, result1.scores)

    # Second run with 1 case - should NOT include scores from first run
    context2 = Braintrust::Eval::Context.build(
      task: task,
      scorers: [scorer],
      cases: [{input: "c", expected: "WRONG"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner2 = Braintrust::Eval::Runner.new(context2)
    result2 = runner2.run
    assert_equal({"exact" => [0.0]}, result2.scores)
  end

  # ============================================
  # Runner#run tests - on_progress callback
  # ============================================

  def test_on_progress_called_for_each_case
    progress_calls = []
    runner = build_simple_runner(
      task: ->(input:) { input.upcase },
      cases: [{input: "a"}, {input: "b"}, {input: "c"}],
      on_progress: ->(data) { progress_calls << data }
    )

    runner.run

    assert_equal 3, progress_calls.length
  end

  def test_on_progress_receives_output_data
    progress_calls = []
    runner = build_simple_runner(
      task: ->(input:) { input.upcase },
      cases: [{input: "hello"}],
      on_progress: ->(data) { progress_calls << data }
    )

    runner.run

    assert_equal "HELLO", progress_calls.first["data"]
  end

  def test_on_progress_receives_scores
    scorer = Braintrust::Scorer.new("exact") { |expected:, output:| (output == expected) ? 1.0 : 0.0 }
    progress_calls = []
    runner = build_simple_runner(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello", expected: "HELLO"}],
      on_progress: ->(data) { progress_calls << data }
    )

    runner.run

    assert_equal({"exact" => 1.0}, progress_calls.first["scores"])
  end

  def test_on_progress_receives_error_on_task_failure
    progress_calls = []
    runner = build_simple_runner(
      task: -> { raise "boom" },
      cases: [{input: "x"}],
      on_progress: ->(data) { progress_calls << data }
    )

    runner.run

    assert_equal 1, progress_calls.length
    assert_match(/boom/, progress_calls.first["error"])
  end

  def test_on_progress_not_required
    runner = build_simple_runner(
      task: ->(input:) { input.upcase },
      cases: [{input: "hello"}]
    )

    result = runner.run

    assert result.success?
  end

  def test_on_progress_with_parallelism
    progress_calls = Queue.new
    runner = build_simple_runner(
      task: ->(input:) { input.upcase },
      cases: [{input: "a"}, {input: "b"}, {input: "c"}],
      on_progress: ->(data) { progress_calls << data }
    )

    runner.run(parallelism: 2)

    assert_equal 3, progress_calls.size
  end

  def test_result_scores_still_collected_with_on_progress
    scorer = Braintrust::Scorer.new("exact") { |expected:, output:| (output == expected) ? 1.0 : 0.0 }
    runner = build_simple_runner(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [
        {input: "hello", expected: "HELLO"},
        {input: "world", expected: "WORLD"}
      ],
      on_progress: ->(data) {}
    )

    result = runner.run

    assert_equal({"exact" => [1.0, 1.0]}, result.scores)
  end

  # ============================================
  # Runner#run tests - parent parameter
  # ============================================

  def test_runner_with_explicit_parent_sets_parent_attr
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "hello", expected: "HELLO"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider,
      parent: {object_type: "project_logs", object_id: "proj-789"}
    )
    runner = Braintrust::Eval::Runner.new(context)

    runner.run

    spans = rig.exporter.finished_spans
    eval_spans = spans.select { |s| s.name == "eval" }

    assert_equal 1, eval_spans.length
    assert_equal "project_logs:proj-789", eval_spans[0].attributes["braintrust.parent"]
  end

  def test_runner_parent_overrides_experiment_id
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider,
      parent: {object_type: "experiment", object_id: "exp-override"}
    )
    runner = Braintrust::Eval::Runner.new(context)

    runner.run

    spans = rig.exporter.finished_spans
    eval_span = spans.find { |s| s.name == "eval" }

    # parent: should take precedence over experiment_id
    assert_equal "experiment:exp-override", eval_span.attributes["braintrust.parent"]
  end

  def test_runner_without_parent_or_experiment_id_has_nil_parent
    # Use bare tracer provider without Braintrust SpanProcessor
    # (SpanProcessor injects a default parent from state.default_project)
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    tracer_provider.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
    )

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "hello"}],
      tracer_provider: tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)

    runner.run

    spans = exporter.finished_spans
    eval_span = spans.find { |s| s.name == "eval" }

    assert_nil eval_span.attributes["braintrust.parent"]
  end

  # ============================================
  # Runner#run tests - trace in scorer
  # ============================================

  def test_scorer_declaring_trace_receives_eval_trace
    rig = setup_otel_test_rig
    received_trace = nil

    scorer = Braintrust::Scorer.new("trace_reader") { |output:, trace:|
      received_trace = trace
      1.0
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello", expected: "HELLO"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)
    result = runner.run

    assert result.success?
    assert_instance_of Braintrust::Eval::Trace, received_trace
  end

  def test_scorer_without_trace_still_works
    rig = setup_otel_test_rig

    # Scorer declares only output: and expected: — no trace:
    scorer = Braintrust::Scorer.new("simple") { |output:, expected:|
      (output == expected) ? 1.0 : 0.0
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello", expected: "HELLO"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)
    result = runner.run

    assert result.success?
    assert_equal({"simple" => [1.0]}, result.scores)
  end

  def test_trace_is_nil_when_state_missing
    # Use bare tracer provider without Braintrust state
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    tracer_provider.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
    )

    received_trace = :not_called

    scorer = Braintrust::Scorer.new("trace_check") { |output:, trace: nil|
      received_trace = trace
      1.0
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      tracer_provider: tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)
    result = runner.run

    assert result.success?
    assert_nil received_trace
  end

  def test_trace_is_nil_when_experiment_id_missing
    rig = setup_otel_test_rig

    received_trace = :not_called

    scorer = Braintrust::Scorer.new("trace_check") { |output:, trace: nil|
      received_trace = trace
      1.0
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      state: rig.state,
      tracer_provider: rig.tracer_provider
      # No experiment_id
    )
    runner = Braintrust::Eval::Runner.new(context)
    result = runner.run

    assert result.success?
    assert_nil received_trace
  end

  def test_trace_is_nil_when_task_fails
    rig = setup_otel_test_rig

    received_trace = :not_called

    scorer = Braintrust::Scorer.new("trace_check") { |output:, trace: nil|
      received_trace = trace
      1.0
    }

    context = Braintrust::Eval::Context.build(
      task: -> { raise "task boom" },
      scorers: [scorer],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)
    result = runner.run

    # Task failed, so scorer never ran — trace never assigned
    assert_equal :not_called, received_trace
    refute result.success?
  end

  def test_trace_works_with_parallelism
    rig = setup_otel_test_rig
    received_traces = []
    mutex = Mutex.new

    scorer = Braintrust::Scorer.new("trace_reader") { |output:, trace:|
      mutex.synchronize { received_traces << trace }
      1.0
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "a"}, {input: "b"}, {input: "c"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    runner = Braintrust::Eval::Runner.new(context)
    result = runner.run(parallelism: 3)

    assert result.success?
    assert_equal 3, received_traces.length
    received_traces.each do |trace|
      assert_instance_of Braintrust::Eval::Trace, trace
    end
  end

  private

  def build_simple_runner(task:, cases:, scorers: [], on_progress: nil)
    @simple_rig ||= setup_otel_test_rig
    context = Braintrust::Eval::Context.build(
      task: task,
      scorers: scorers,
      cases: cases,
      on_progress: on_progress,
      tracer_provider: @simple_rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context)
  end
end
