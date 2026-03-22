# frozen_string_literal: true

require "test_helper"
require "braintrust/eval"

# Unit tests for Eval::Context and Context::Factory
class Braintrust::Eval::ContextTest < Minitest::Test
  # ============================================
  # Factory#build — task normalization
  # ============================================

  def test_build_passes_through_task_instance
    task = Braintrust::Task.new("my_task") { |input:| input.upcase }
    ctx = build_context(task: task)
    assert_same task, ctx.task
  end

  def test_build_wraps_lambda_task
    ctx = build_context(task: ->(input:) { input.upcase })
    assert_kind_of Braintrust::Task, ctx.task
    assert_equal "HELLO", ctx.task.call(input: "hello")
  end

  def test_build_wraps_legacy_positional_lambda_task
    suppress_logs do
      ctx = build_context(task: ->(input) { input.upcase })
      assert_kind_of Braintrust::Task, ctx.task
      assert_equal "HELLO", ctx.task.call(input: "hello")
    end
  end

  def test_build_wraps_callable_class_task
    callable = Class.new do
      def initialize(prefix)
        @prefix = prefix
      end

      def name
        "prefixer"
      end

      def call(input:)
        "#{@prefix}: #{input}"
      end
    end.new("Result")

    ctx = build_context(task: callable)
    assert_kind_of Braintrust::Task, ctx.task
    assert_equal "prefixer", ctx.task.name
    assert_equal "Result: hello", ctx.task.call(input: "hello")
  end

  def test_build_callable_class_task_preserves_instance_state
    callable = Class.new do
      attr_accessor :mode

      def call(input:)
        (mode == :shout) ? input.upcase : input.downcase
      end
    end.new

    callable.mode = :shout
    ctx = build_context(task: callable)
    assert_equal "HELLO", ctx.task.call(input: "hello")

    callable.mode = :whisper
    assert_equal "hello", ctx.task.call(input: "HELLO")
  end

  def test_build_callable_class_task_without_name
    callable = Class.new do
      def call(input:)
        input.upcase
      end
    end.new

    ctx = build_context(task: callable)
    assert_kind_of Braintrust::Task, ctx.task
    assert_equal "task", ctx.task.name
    assert_equal "HELLO", ctx.task.call(input: "hello")
  end

  # ============================================
  # Factory#build — scorer normalization
  # ============================================

  def test_build_passes_through_scorer_instance
    scorer = Braintrust::Scorer.new("exact") { |expected:, output:| (output == expected) ? 1.0 : 0.0 }
    ctx = build_context(scorers: [scorer])
    assert_equal 1, ctx.scorers.length
    assert_same scorer, ctx.scorers.first
  end

  def test_build_wraps_lambda_scorer
    lam = ->(expected:, output:) { (output == expected) ? 1.0 : 0.0 }
    ctx = build_context(scorers: [lam])
    assert_equal 1, ctx.scorers.length
    assert_kind_of Braintrust::Scorer, ctx.scorers.first
    assert_equal [{score: 1.0, metadata: nil, name: "scorer"}],
      ctx.scorers.first.call(input: "x", expected: "YES", output: "YES")
  end

  def test_build_wraps_callable_class_scorer
    callable = Class.new do
      def initialize(threshold)
        @threshold = threshold
      end

      def name
        "threshold_scorer"
      end

      def call(expected:, output:)
        (output == expected) ? 1.0 : @threshold
      end
    end.new(0.5)

    ctx = build_context(scorers: [callable])
    assert_equal 1, ctx.scorers.length
    assert_equal "threshold_scorer", ctx.scorers.first.name
    assert_equal [{score: 0.5, metadata: nil, name: "threshold_scorer"}],
      ctx.scorers.first.call(input: "x", expected: "a", output: "b")
  end

  def test_build_wraps_lambda_scorer_alternate_arg_order
    lam = ->(output:, expected:) { (output == expected) ? 1.0 : 0.0 }
    ctx = build_context(scorers: [lam])
    assert_equal 1, ctx.scorers.length
    assert_kind_of Braintrust::Scorer, ctx.scorers.first
    assert_equal [{score: 1.0, metadata: nil, name: "scorer"}],
      ctx.scorers.first.call(input: "x", expected: "a", output: "a")
  end

  def test_build_callable_class_scorer_without_name
    callable = Class.new do
      def call(output:, expected:)
        (output == expected) ? 1.0 : 0.0
      end
    end.new

    ctx = build_context(scorers: [callable])
    assert_equal 1, ctx.scorers.length
    assert_equal "scorer", ctx.scorers.first.name
    assert_equal [{score: 1.0, metadata: nil, name: "scorer"}],
      ctx.scorers.first.call(input: "x", expected: "a", output: "a")
  end

  # ============================================
  # Factory#build — scorer slug/ID resolution
  # ============================================

  def test_build_resolves_string_scorer_slug
    fake_scorer = Braintrust::Scorer.new("resolved") { |**| 1.0 }
    resolved_kwargs = nil

    Braintrust::Functions.stub(:scorer, ->(**kw) {
      resolved_kwargs = kw
      fake_scorer
    }) do
      ctx = Braintrust::Eval::Context.build(
        task: ->(input:) { input },
        scorers: ["my-scorer-slug"],
        cases: [{input: "a"}],
        project_name: "my-project",
        state: :fake_state,
        tracer_provider: :fake_tp
      )

      assert_equal 1, ctx.scorers.length
      assert_same fake_scorer, ctx.scorers.first
      assert_equal "my-project", resolved_kwargs[:project]
      assert_equal "my-scorer-slug", resolved_kwargs[:slug]
      assert_equal :fake_state, resolved_kwargs[:state]
      assert_equal :fake_tp, resolved_kwargs[:tracer_provider]
    end
  end

  def test_build_string_scorer_slug_raises_without_project
    error = assert_raises(ArgumentError) do
      build_context(scorers: ["some-slug"])
    end
    assert_match(/project is required/, error.message)
  end

  def test_build_resolves_scorer_id
    fake_scorer = Braintrust::Scorer.new("resolved") { |**| 1.0 }
    resolved_kwargs = nil

    Braintrust::Functions.stub(:scorer, ->(**kw) {
      resolved_kwargs = kw
      fake_scorer
    }) do
      scorer_id = Braintrust::Scorer::ID.new(function_id: "func-abc", version: "v3")
      ctx = Braintrust::Eval::Context.build(
        task: ->(input:) { input },
        scorers: [scorer_id],
        cases: [{input: "a"}],
        state: :fake_state,
        tracer_provider: :fake_tp
      )

      assert_equal 1, ctx.scorers.length
      assert_same fake_scorer, ctx.scorers.first
      assert_equal "func-abc", resolved_kwargs[:id]
      assert_equal "v3", resolved_kwargs[:version]
      assert_equal :fake_state, resolved_kwargs[:state]
      assert_equal :fake_tp, resolved_kwargs[:tracer_provider]
    end
  end

  def test_build_resolves_deprecated_scorer_id_alias
    fake_scorer = Braintrust::Scorer.new("resolved") { |**| 1.0 }
    resolved_kwargs = nil

    Braintrust::Functions.stub(:scorer, ->(**kw) {
      resolved_kwargs = kw
      fake_scorer
    }) do
      scorer_id = Braintrust::ScorerId.new(function_id: "func-legacy", version: "v1")
      ctx = Braintrust::Eval::Context.build(
        task: ->(input:) { input },
        scorers: [scorer_id],
        cases: [{input: "a"}],
        state: :fake_state
      )

      assert_equal 1, ctx.scorers.length
      assert_same fake_scorer, ctx.scorers.first
      assert_equal "func-legacy", resolved_kwargs[:id]
      assert_equal "v1", resolved_kwargs[:version]
    end
  end

  # ============================================
  # Factory#build — cases normalization
  # ============================================

  def test_build_passes_through_cases_instance
    cases = Braintrust::Eval::Cases.new([{input: "a"}])
    ctx = build_context(cases: cases)
    assert_same cases, ctx.cases
  end

  def test_build_wraps_array_cases
    ctx = build_context(cases: [{input: "a"}, {input: "b"}])
    assert_instance_of Braintrust::Eval::Cases, ctx.cases
    assert_equal 2, ctx.cases.to_a.length
  end

  def test_build_wraps_custom_enumerable_cases
    enum = Object.new
    def enum.each(&block)
      [{input: "a"}, {input: "b"}].each(&block)
    end

    ctx = build_context(cases: enum)
    assert_instance_of Braintrust::Eval::Cases, ctx.cases
  end

  def test_build_rejects_non_enumerable_cases
    assert_raises(ArgumentError) do
      build_context(cases: "not enumerable")
    end
  end

  # ============================================
  # Factory#build — parent resolution
  # ============================================

  def test_build_extracts_generation_from_parent
    ctx = Braintrust::Eval::Context.build(
      task: ->(input:) { input },
      scorers: [],
      cases: [{input: "a"}],
      parent: {object_type: "experiment_id", object_id: "exp-1", generation: 42}
    )
    assert_equal 42, ctx.generation
    assert_equal "experiment_id:exp-1", ctx.parent_span_attr
  end

  def test_build_nil_parent
    ctx = build_context
    assert_nil ctx.parent_span_attr
    assert_nil ctx.generation
  end

  # ============================================
  # Context.build — field pass-through
  # ============================================

  def test_build_passes_through_all_fields
    on_progress = ->(_) {}
    ctx = Braintrust::Eval::Context.build(
      task: ->(input:) { input },
      scorers: [],
      cases: [{input: "a"}],
      experiment_id: "eid",
      experiment_name: "ename",
      project_id: "pid",
      project_name: "pname",
      on_progress: on_progress
    )
    assert_equal "eid", ctx.experiment_id
    assert_equal "ename", ctx.experiment_name
    assert_equal "pid", ctx.project_id
    assert_equal "pname", ctx.project_name
    assert_same on_progress, ctx.on_progress
    assert_nil ctx.parent_span_attr
    assert_nil ctx.generation
  end

  def test_build_defaults_tracer_provider_to_global
    ctx = build_context
    assert_same OpenTelemetry.tracer_provider, ctx.tracer_provider
  end

  def test_build_uses_explicit_tracer_provider
    fake_tp = Object.new
    ctx = Braintrust::Eval::Context.build(
      task: ->(input:) { input },
      scorers: [],
      cases: [{input: "a"}],
      tracer_provider: fake_tp
    )
    assert_same fake_tp, ctx.tracer_provider
  end

  private

  def build_context(task: ->(input:) { input }, scorers: [], cases: [{input: "a"}], **kwargs)
    Braintrust::Eval::Context.build(task: task, scorers: scorers, cases: cases, **kwargs)
  end
end
