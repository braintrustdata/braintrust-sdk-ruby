# frozen_string_literal: true

require "test_helper"
require "braintrust/task"
require "braintrust/scorer"

class Braintrust::Internal::CallableTest < Minitest::Test
  # ============================================
  # Keyword filtering (block with subset of kwargs, no **)
  # ============================================

  def test_keyword_block_receives_only_declared_kwargs
    scorer = Braintrust::Scorer.new("subset") do |output:, expected:|
      {output: output, expected: expected}
    end

    result = scorer.call(
      input: "apple", expected: "fruit", output: "fruit",
      metadata: {key: "val"}, tags: ["t1"]
    )

    assert_equal({output: "fruit", expected: "fruit"}, result)
  end

  def test_keyword_block_with_single_kwarg
    task = Braintrust::Task.new("single") { |input:| input.upcase }

    result = task.call(input: "hello", metadata: {}, tags: nil)

    assert_equal "HELLO", result
  end

  # ============================================
  # Keyrest passthrough (block with **)
  # ============================================

  def test_keyrest_block_receives_all_kwargs
    received = nil
    scorer = Braintrust::Scorer.new("all") do |output:, expected:, **rest|
      received = rest
      1.0
    end

    scorer.call(input: "a", expected: "b", output: "c", metadata: {}, tags: ["t"])

    assert_equal({input: "a", metadata: {}, tags: ["t"]}, received)
  end

  def test_bare_keyrest_receives_everything
    received = nil
    scorer = Braintrust::Scorer.new("bare") do |**kw|
      received = kw
      1.0
    end

    scorer.call(input: "a", expected: "b", output: "c")

    assert_equal({input: "a", expected: "b", output: "c"}, received)
  end

  # ============================================
  # Positional delegation
  # ============================================

  def test_positional_task_block_auto_wrapped
    task = Braintrust::Task.new("pos") { |input| input.upcase }

    result = task.call(input: "hello", metadata: {}, tags: nil)

    assert_equal "HELLO", result
  end

  def test_positional_scorer_block_arity_3
    scorer = Braintrust::Scorer.new("pos3") { |i, e, o| (o == e) ? 1.0 : 0.0 }

    assert_equal 1.0, scorer.call(input: "a", expected: "b", output: "b", metadata: {})
  end

  def test_positional_scorer_block_arity_4
    scorer = Braintrust::Scorer.new("pos4") { |i, e, o, m| m[:threshold] }

    assert_equal 0.9, scorer.call(input: "a", expected: "b", output: "c", metadata: {threshold: 0.9})
  end

  # ============================================
  # Zero arity
  # ============================================

  def test_zero_arity_block_passes_through
    scorer = Braintrust::Scorer.new("zero") { 42 }

    assert_equal 42, scorer.call(input: "a", expected: "b", output: "c")
  end

  # ============================================
  # Default naming
  # ============================================

  def test_task_default_name_is_task
    task = Braintrust::Task.new { |input:| input }
    assert_equal "task", task.name
  end

  def test_scorer_default_name_is_scorer
    scorer = Braintrust::Scorer.new { |**| 1.0 }
    assert_equal "scorer", scorer.name
  end

  def test_subclass_name_derived_from_class
    klass = Class.new(Braintrust::Scorer) do
      def call(**)
        1.0
      end
    end

    Braintrust.stub_const(:FuzzyMatch, klass) do
      scorer = klass.new
      assert_equal "fuzzy_match", scorer.name
    end
  end

  def test_explicit_name_takes_precedence
    task = Braintrust::Task.new("custom") { |input:| input }
    assert_equal "custom", task.name
  end

  # ============================================
  # Subclass with call override (no block)
  # ============================================

  def test_subclass_call_override_not_affected_by_filtering
    klass = Class.new(Braintrust::Scorer) do
      def call(output:, expected:, **)
        (output == expected) ? 1.0 : 0.0
      end
    end

    scorer = klass.new
    # Subclass overrides call directly, no block wrapping involved
    assert_equal 1.0, scorer.call(input: "a", expected: "b", output: "b", metadata: {}, tags: [])
  end

  # ============================================
  # Error cases
  # ============================================

  def test_not_implemented_raises_without_block_or_override
    klass = Class.new(Braintrust::Scorer)
    scorer = klass.new

    assert_raises(NotImplementedError) { scorer.call(output: "a") }
  end

  def test_invalid_positional_arity_raises_for_task
    assert_raises(ArgumentError) do
      Braintrust::Task.new("bad") { |a, b| a }
    end
  end

  def test_invalid_positional_arity_raises_for_scorer
    assert_raises(ArgumentError) do
      Braintrust::Scorer.new("bad") { |a, b| a }
    end
  end
end
