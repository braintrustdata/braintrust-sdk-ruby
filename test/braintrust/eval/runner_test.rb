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

  def test_runner_eval_span_has_case_metadata
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "hello", expected: "HELLO", metadata: {difficulty: "easy", category: "greeting"}}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context).run

    eval_span = rig.exporter.finished_spans.find { |s| s.name == "eval" }
    metadata = JSON.parse(eval_span.attributes["braintrust.metadata"])

    assert_equal "easy", metadata["difficulty"]
    assert_equal "greeting", metadata["category"]
  end

  def test_runner_eval_span_input_json_wrapped
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
    Braintrust::Eval::Runner.new(context).run

    eval_span = rig.exporter.finished_spans.find { |s| s.name == "eval" }
    input_json = JSON.parse(eval_span.attributes["braintrust.input_json"])

    assert_equal({"input" => "hello"}, input_json)
  end

  def test_runner_eval_span_tags_as_array
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "hello", tags: ["fast", "regression"]}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context).run

    eval_span = rig.exporter.finished_spans.find { |s| s.name == "eval" }
    tags = eval_span.attributes["braintrust.tags"]

    assert_instance_of Array, tags
    assert_equal ["fast", "regression"], tags
  end

  def test_runner_eval_span_output_json_null_on_task_error
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: -> { raise "boom" },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context).run

    eval_span = rig.exporter.finished_spans.find { |s| s.name == "eval" }
    output_json = JSON.parse(eval_span.attributes["braintrust.output_json"])

    assert_equal({"output" => nil}, output_json)
  end

  def test_runner_eval_span_output_json_wrapped
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
    Braintrust::Eval::Runner.new(context).run

    eval_span = rig.exporter.finished_spans.find { |s| s.name == "eval" }
    output_json = JSON.parse(eval_span.attributes["braintrust.output_json"])

    assert_equal({"output" => "HELLO"}, output_json)
  end

  def test_runner_eval_spans_are_independent_roots
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 1.0 }],
      cases: [{input: "a"}, {input: "b"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context).run

    eval_spans = rig.exporter.finished_spans.select { |s| s.name == "eval" }
    assert_equal 2, eval_spans.length

    # Each eval span should have a unique trace ID (independent roots)
    trace_ids = eval_spans.map { |s| s.hex_trace_id }.uniq
    assert_equal 2, trace_ids.length, "Each eval case should be its own trace"

    # Eval spans should not have a parent span
    invalid_hex = OpenTelemetry::Trace::INVALID_SPAN_ID.unpack1("H*")
    eval_spans.each do |span|
      assert_equal invalid_hex, span.hex_parent_span_id,
        "Eval span should be a root span with no parent"
    end
  end

  def test_runner_eval_span_no_metadata_when_nil
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
      tracer_provider: rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context).run

    eval_span = rig.exporter.finished_spans.find { |s| s.name == "eval" }
    assert_nil eval_span.attributes["braintrust.metadata"]
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

  def test_runner_run_creates_per_scorer_spans
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
      tracer_provider: rig.tracer_provider,
      parent: {object_type: "experiment_id", object_id: "exp-123"}
    )
    runner = Braintrust::Eval::Runner.new(context)

    runner.run

    spans = rig.exporter.finished_spans
    score_spans = spans.select { |s| ["accuracy", "relevance"].include?(s.name) }

    # One span per scorer, not one shared span
    assert_equal 2, score_spans.length
    score_spans.each do |span|
      assert_equal "experiment_id:exp-123", span.attributes["braintrust.parent"]
    end
  end

  def test_runner_run_records_scores_on_per_scorer_spans
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
    score_spans = spans.select { |s| ["accuracy", "relevance"].include?(s.name) }

    scores_by_name = score_spans.each_with_object({}) do |span, h|
      parsed = JSON.parse(span.attributes["braintrust.scores"])
      h.merge!(parsed)
    end
    assert_equal({"accuracy" => 0.95, "relevance" => 0.87}, scores_by_name)

    # Result still aggregates all scores
    assert_equal({"accuracy" => [0.95], "relevance" => [0.87]}, result.scores)
  end

  def test_runner_scorer_span_attributes
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
      tracer_provider: rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context).run

    spans = rig.exporter.finished_spans
    scorer_span = spans.find { |s| s.name == "exact" }
    span_attrs = JSON.parse(scorer_span.attributes["braintrust.span_attributes"])

    assert_equal "score", span_attrs["type"]
    assert_equal "exact", span_attrs["name"]
    assert_equal "scorer", span_attrs["purpose"]
  end

  def test_runner_scorer_span_has_input_and_output
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [Braintrust::Scorer.new("exact") { 0.5 }],
      cases: [{input: "hello", expected: "HELLO", metadata: {key: "val"}}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context).run

    spans = rig.exporter.finished_spans
    scorer_span = spans.find { |s| s.name == "exact" }

    input = JSON.parse(scorer_span.attributes["braintrust.input_json"])
    assert_equal "hello", input["input"]
    assert_equal "HELLO", input["expected"]
    assert_equal "HELLO", input["output"]
    assert_equal({"key" => "val"}, input["metadata"])

    output = JSON.parse(scorer_span.attributes["braintrust.output_json"])
    assert_equal({"exact" => 0.5}, output)
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

  # ============================================
  # Runner#run tests - structured scorer returns
  # ============================================

  def test_scorer_hash_return_extracts_numeric_score
    rig = setup_otel_test_rig

    scorer = Braintrust::Scorer.new("structured") { |output:|
      {score: 0.75, metadata: {reason: "partial match"}}
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    result = Braintrust::Eval::Runner.new(context).run

    assert result.success?
    assert_equal({"structured" => [0.75]}, result.scores)
  end

  def test_scorer_hash_return_name_override
    rig = setup_otel_test_rig

    scorer = Braintrust::Scorer.new("original") { |output:|
      {score: 0.9, name: "overridden"}
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    result = Braintrust::Eval::Runner.new(context).run

    assert result.success?
    assert_equal({"overridden" => [0.9]}, result.scores)
    assert_nil result.scores["original"]
  end

  def test_scorer_hash_return_metadata_on_span
    rig = setup_otel_test_rig

    scorer = Braintrust::Scorer.new("meta_scorer") { |output:|
      {score: 1.0, metadata: {failure_type: "none", confidence: 0.99}}
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context).run

    score_span = rig.exporter.finished_spans.find { |s| s.name == "meta_scorer" }
    metadata = JSON.parse(score_span.attributes["braintrust.metadata"])
    assert_equal({"failure_type" => "none", "confidence" => 0.99}, metadata)
  end

  def test_scorer_hash_without_score_key
    rig = setup_otel_test_rig

    scorer = Braintrust::Scorer.new("no_score_key") { |output:|
      {metadata: {reason: "test"}}
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    result = Braintrust::Eval::Runner.new(context).run

    assert result.success?
    # nil score is not Numeric, so not collected for stats
    assert_equal({}, result.scores)
  end

  def test_scorer_hash_with_nil_score
    rig = setup_otel_test_rig

    scorer = Braintrust::Scorer.new("nil_score") { |output:|
      {score: nil, metadata: {reason: "could not score"}}
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    result = Braintrust::Eval::Runner.new(context).run

    assert result.success?
    assert_equal({}, result.scores)

    # Metadata should still be logged even with nil score
    score_span = rig.exporter.finished_spans.find { |s| s.name == "nil_score" }
    metadata = JSON.parse(score_span.attributes["braintrust.metadata"])
    assert_equal({"reason" => "could not score"}, metadata)
  end

  def test_multiple_scorers_mixed_return_types
    rig = setup_otel_test_rig

    scorer1 = Braintrust::Scorer.new("numeric") { 0.8 }
    scorer2 = Braintrust::Scorer.new("structured") { {score: 0.6, metadata: {detail: "partial"}} }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer1, scorer2],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    result = Braintrust::Eval::Runner.new(context).run

    assert result.success?
    assert_equal({"numeric" => [0.8], "structured" => [0.6]}, result.scores)

    # Only structured scorer's span has metadata
    score_spans = rig.exporter.finished_spans.select { |s| ["numeric", "structured"].include?(s.name) }
    structured_span = score_spans.find { |s| s.name == "structured" }
    numeric_span = score_spans.find { |s| s.name == "numeric" }

    metadata = JSON.parse(structured_span.attributes["braintrust.metadata"])
    assert_equal({"detail" => "partial"}, metadata)
    assert_nil numeric_span.attributes["braintrust.metadata"]
  end

  def test_scorer_hash_return_scores_on_span_are_extracted
    rig = setup_otel_test_rig

    scorer = Braintrust::Scorer.new("structured") { {score: 0.75, metadata: {x: 1}} }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context).run

    score_span = rig.exporter.finished_spans.find { |s| s.name == "structured" }
    scores = JSON.parse(score_span.attributes["braintrust.scores"])
    # Should be the numeric value, not the hash
    assert_equal 0.75, scores["structured"]
  end

  def test_on_progress_receives_extracted_score_from_hash
    progress_calls = []
    scorer = Braintrust::Scorer.new("structured") { {score: 0.5, metadata: {x: 1}} }
    runner = build_simple_runner(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      on_progress: ->(data) { progress_calls << data }
    )

    runner.run

    assert_equal({"structured" => 0.5}, progress_calls.first["scores"])
  end

  def test_scorer_no_metadata_attr_when_all_numeric
    rig = setup_otel_test_rig

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [
        Braintrust::Scorer.new("a") { 0.5 },
        Braintrust::Scorer.new("b") { 1.0 }
      ],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    Braintrust::Eval::Runner.new(context).run

    score_span = rig.exporter.finished_spans.find { |s| s.name == "a" }
    # No metadata attribute should be set when no scorers return metadata
    assert_nil score_span.attributes["braintrust.metadata"]
  end

  def test_scorer_hash_with_non_hash_metadata_ignored
    rig = setup_otel_test_rig

    scorer = Braintrust::Scorer.new("str_meta") { |output:|
      {score: 0.5, metadata: "not a hash"}
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    result = Braintrust::Eval::Runner.new(context).run

    assert result.success?
    assert_equal({"str_meta" => [0.5]}, result.scores)

    # Non-hash metadata should not be logged
    score_span = rig.exporter.finished_spans.find { |s| s.name == "str_meta" }
    assert_nil score_span.attributes["braintrust.metadata"]
  end

  def test_scorer_hash_return_multiple_cases
    rig = setup_otel_test_rig

    scorer = Braintrust::Scorer.new("quality") { |output:|
      {score: output.length.to_f / 10, metadata: {length: output.length}}
    }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hi"}, {input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    result = Braintrust::Eval::Runner.new(context).run

    assert result.success?
    assert_equal({"quality" => [0.2, 0.5]}, result.scores)
  end

  def test_scorer_empty_hash_return
    rig = setup_otel_test_rig

    scorer = Braintrust::Scorer.new("empty") { |output:| {} }

    context = Braintrust::Eval::Context.build(
      task: ->(input:) { input.upcase },
      scorers: [scorer],
      cases: [{input: "hello"}],
      experiment_id: "exp-123",
      experiment_name: "test-experiment",
      project_id: "proj-456",
      project_name: "test-project",
      state: rig.state,
      tracer_provider: rig.tracer_provider
    )
    result = Braintrust::Eval::Runner.new(context).run

    assert result.success?
    # Empty hash has no :score key, so score is nil and not collected
    assert_equal({}, result.scores)
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
