# frozen_string_literal: true

require "test_helper"
require "braintrust/eval"

# Unit tests for Eval::Context and Context::Factory
class Braintrust::Eval::ContextTest < Minitest::Test
  # ============================================
  # normalize_task
  # ============================================

  def test_normalize_task_passes_through_task_instance
    task = Braintrust::Task.new("my_task") { |input:| input.upcase }
    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_task(task)
    assert_same task, result
  end

  def test_normalize_task_wraps_lambda_with_kwargs
    lam = ->(input:) { input.upcase }
    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_task(lam)
    assert_kind_of Braintrust::Task, result
    assert_equal "HELLO", result.call(input: "hello")
  end

  def test_normalize_task_wraps_legacy_positional_lambda
    suppress_logs do
      lam = ->(input) { input.upcase }
      factory = Braintrust::Eval::Context::Factory.new

      result = factory.normalize_task(lam)
      assert_kind_of Braintrust::Task, result
      assert_equal "HELLO", result.call(input: "hello")
    end
  end

  def test_normalize_task_wraps_callable_class_with_kwargs
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

    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_task(callable)
    assert_kind_of Braintrust::Task, result
    assert_equal "prefixer", result.name
    assert_equal "Result: hello", result.call(input: "hello")
  end

  def test_normalize_task_callable_class_preserves_instance_state
    callable = Class.new do
      attr_accessor :mode

      def call(input:)
        (mode == :shout) ? input.upcase : input.downcase
      end
    end.new

    factory = Braintrust::Eval::Context::Factory.new

    callable.mode = :shout
    task = factory.normalize_task(callable)
    assert_equal "HELLO", task.call(input: "hello")

    callable.mode = :whisper
    assert_equal "hello", task.call(input: "HELLO")
  end

  # ============================================
  # normalize_scorers
  # ============================================

  def test_normalize_scorers_passes_through_scorer_instance
    scorer = Braintrust::Scorer.new("exact") { |expected:, output:| (output == expected) ? 1.0 : 0.0 }
    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_scorers([scorer])
    assert_equal 1, result.length
    assert_same scorer, result.first
  end

  def test_normalize_scorers_wraps_lambda_with_kwargs
    lam = ->(expected:, output:) { (output == expected) ? 1.0 : 0.0 }
    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_scorers([lam])
    assert_equal 1, result.length
    assert_kind_of Braintrust::Scorer, result.first
    assert_equal 1.0, result.first.call(input: "x", expected: "YES", output: "YES")
  end

  def test_normalize_scorers_wraps_callable_class_with_kwargs
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

    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_scorers([callable])
    assert_equal 1, result.length
    assert_equal "threshold_scorer", result.first.name
    assert_equal 0.5, result.first.call(input: "x", expected: "a", output: "b")
  end

  # ============================================
  # normalize_cases
  # ============================================

  def test_normalize_cases_passes_through_cases_instance
    cases = Braintrust::Eval::Cases.new([{input: "a"}])
    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_cases(cases)
    assert_same cases, result
  end

  def test_normalize_cases_wraps_array
    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_cases([{input: "a"}, {input: "b"}])
    assert_instance_of Braintrust::Eval::Cases, result
    assert_equal 2, result.to_a.length
  end

  # ============================================
  # resolve_parent_span_attr
  # ============================================

  def test_resolve_parent_span_attr_returns_nil_for_nil
    factory = Braintrust::Eval::Context::Factory.new
    assert_nil factory.resolve_parent_span_attr(nil)
  end

  def test_resolve_parent_span_attr_formats_correctly
    factory = Braintrust::Eval::Context::Factory.new
    result = factory.resolve_parent_span_attr(object_type: "experiment_id", object_id: "exp-123")
    assert_equal "experiment_id:exp-123", result
  end

  # ============================================
  # Context.build
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

  # ============================================
  # Factory edge cases
  # ============================================

  def test_normalize_task_callable_class_without_name
    callable = Class.new do
      def call(input:)
        input.upcase
      end
    end.new

    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_task(callable)
    assert_kind_of Braintrust::Task, result
    assert_equal "task", result.name
    assert_equal "HELLO", result.call(input: "hello")
  end

  def test_normalize_scorers_wraps_lambda
    lam = ->(output:, expected:) { (output == expected) ? 1.0 : 0.0 }
    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_scorers([lam])
    assert_equal 1, result.length
    assert_kind_of Braintrust::Scorer, result.first
    assert_equal 1.0, result.first.call(input: "x", expected: "a", output: "a")
  end

  def test_normalize_scorers_callable_class_without_name
    callable = Class.new do
      def call(output:, expected:)
        (output == expected) ? 1.0 : 0.0
      end
    end.new

    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_scorers([callable])
    assert_equal 1, result.length
    assert_equal "scorer", result.first.name
    assert_equal 1.0, result.first.call(input: "x", expected: "a", output: "a")
  end

  def test_normalize_cases_rejects_non_enumerable
    factory = Braintrust::Eval::Context::Factory.new

    assert_raises(ArgumentError) do
      factory.normalize_cases("not enumerable")
    end
  end

  def test_normalize_cases_wraps_custom_enumerable
    enum = Object.new
    def enum.each(&block)
      [{input: "a"}, {input: "b"}].each(&block)
    end

    factory = Braintrust::Eval::Context::Factory.new

    result = factory.normalize_cases(enum)
    assert_instance_of Braintrust::Eval::Cases, result
  end

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
end
