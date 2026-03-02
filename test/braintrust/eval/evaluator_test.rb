# frozen_string_literal: true

require "test_helper"
require "braintrust/eval"

class Braintrust::Eval::EvaluatorTest < Minitest::Test
  def setup
    @rig = setup_otel_test_rig
  end

  def test_stores_task
    task = ->(input) { input.upcase }
    evaluator = Braintrust::Eval::Evaluator.new(task: task)

    assert_equal task, evaluator.task
  end

  def test_stores_scorers
    scorer = Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }
    evaluator = Braintrust::Eval::Evaluator.new(scorers: [scorer])

    assert_equal 1, evaluator.scorers.length
    assert_equal "exact", evaluator.scorers.first.name
  end

  def test_defaults_scorers_to_empty_array
    evaluator = Braintrust::Eval::Evaluator.new
    assert_equal [], evaluator.scorers
  end

  def test_stores_parameters
    evaluator = Braintrust::Eval::Evaluator.new(
      parameters: {"temperature" => {type: "number", default: 0.7}}
    )

    assert_equal 0.7, evaluator.parameters["temperature"][:default]
  end

  def test_defaults_parameters_to_empty_hash
    evaluator = Braintrust::Eval::Evaluator.new
    assert_equal({}, evaluator.parameters)
  end

  def test_validate_requires_task
    evaluator = Braintrust::Eval::Evaluator.new

    error = assert_raises(ArgumentError) { evaluator.validate! }
    assert_match(/task/, error.message)
  end

  def test_validate_passes_with_task
    evaluator = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    evaluator.validate! # should not raise
  end

  def test_validate_requires_callable_task
    evaluator = Braintrust::Eval::Evaluator.new(task: "not a callable")

    error = assert_raises(ArgumentError) { evaluator.validate! }
    assert_match(/callable/, error.message)
  end

  def test_run_delegates_to_eval_run
    evaluator = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input.upcase },
      scorers: [
        Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }
      ]
    )

    cases = [{input: "hello", expected: "HELLO"}]
    result = evaluator.run(cases, quiet: true, tracer_provider: @rig.tracer_provider)

    assert_instance_of Braintrust::Eval::Result, result
    assert_equal [1.0], result.scores["exact"]
  end

  def test_run_passes_on_progress
    evaluator = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    progress_events = []
    cases = [{input: "a"}, {input: "b"}]
    evaluator.run(cases, on_progress: ->(data) { progress_events << data }, quiet: true, tracer_provider: @rig.tracer_provider)

    assert_equal 2, progress_events.length
  end

  # --- Subclass pattern ---

  def test_subclass_overrides_task
    klass = Class.new(Braintrust::Eval::Evaluator) do
      def task
        ->(input) { input.upcase }
      end
    end

    evaluator = klass.new
    assert_equal "HELLO", evaluator.task.call("hello")
  end

  def test_subclass_overrides_scorers
    klass = Class.new(Braintrust::Eval::Evaluator) do
      def scorers
        [Braintrust::Eval.scorer("always_one") { |i, e, o| 1.0 }]
      end
    end

    evaluator = klass.new
    assert_equal 1, evaluator.scorers.length
    assert_equal "always_one", evaluator.scorers.first.name
  end

  def test_subclass_run
    klass = Class.new(Braintrust::Eval::Evaluator) do
      def task
        ->(input) { input.upcase }
      end

      def scorers
        [Braintrust::Eval.scorer("exact") { |i, e, o| (o == e) ? 1.0 : 0.0 }]
      end
    end

    evaluator = klass.new
    result = evaluator.run([{input: "hello", expected: "HELLO"}], quiet: true, tracer_provider: @rig.tracer_provider)

    assert_instance_of Braintrust::Eval::Result, result
    assert_equal [1.0], result.scores["exact"]
  end

  def test_subclass_with_constructor_args
    klass = Class.new(Braintrust::Eval::Evaluator) do
      def initialize(model:, **kwargs)
        super(**kwargs)
        @model = model
      end

      def task
        model = @model
        ->(input) { "#{model}: #{input}" }
      end
    end

    evaluator = klass.new(model: "gpt-4")
    assert_equal "gpt-4: hello", evaluator.task.call("hello")
  end

  # --- Extended run with additional scorers ---

  def test_run_merges_additional_scorers
    local_scorer = Braintrust::Eval.scorer("local") { |i, e, o| 1.0 }
    extra_scorer = Braintrust::Eval.scorer("extra") { |i, e, o| 0.5 }

    evaluator = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input.upcase },
      scorers: [local_scorer]
    )

    result = evaluator.run(
      [{input: "hello", expected: "HELLO"}],
      scorers: [extra_scorer],
      quiet: true,
      tracer_provider: @rig.tracer_provider
    )

    assert_instance_of Braintrust::Eval::Result, result
    assert result.scores.key?("local"), "Should have local scorer"
    assert result.scores.key?("extra"), "Should have extra scorer"
  end

  def test_run_without_additional_scorers_uses_own
    local_scorer = Braintrust::Eval.scorer("local") { |i, e, o| 1.0 }

    evaluator = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input.upcase },
      scorers: [local_scorer]
    )

    result = evaluator.run(
      [{input: "hello", expected: "HELLO"}],
      quiet: true,
      tracer_provider: @rig.tracer_provider
    )

    assert_instance_of Braintrust::Eval::Result, result
    assert result.scores.key?("local")
  end

  def test_run_forwards_state_parameter
    evaluator = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input.upcase },
      scorers: [Braintrust::Eval.scorer("s") { |i, e, o| 1.0 }]
    )

    # Spy on Eval.run to verify state is forwarded
    received_state = :not_called
    Braintrust::Eval.stub(:run, ->(task:, scorers:, state:, **rest) {
      received_state = state
      Braintrust::Eval::Result.new(
        experiment_id: nil, experiment_name: nil,
        project_id: nil, project_name: nil,
        permalink: nil, scores: {"s" => [1.0]}, errors: [], duration: 0.01
      )
    }) do
      evaluator.run(
        [{input: "hello"}],
        state: @rig.state,
        quiet: true,
        tracer_provider: @rig.tracer_provider
      )
    end

    assert_same @rig.state, received_state, "state: should be forwarded to Eval.run"
  end

  def test_run_forwards_update_parameter
    evaluator = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input.upcase },
      scorers: [Braintrust::Eval.scorer("s") { |i, e, o| 1.0 }]
    )

    # Should not raise when update: true is passed (no project, so no API call)
    result = evaluator.run(
      [{input: "hello"}],
      quiet: true,
      update: true,
      tracer_provider: @rig.tracer_provider
    )

    assert result.success?
  end
end
