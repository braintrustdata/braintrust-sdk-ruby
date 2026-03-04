# frozen_string_literal: true

require "test_helper"
require "braintrust/scorer"

class Braintrust::ScorerTest < Minitest::Test
  # ============================================
  # Scorer.new with block (inline scorers)
  # ============================================

  def test_scorer_with_kwargs_block
    scorer = Braintrust::Scorer.new("exact_match") do |output:, expected:, **|
      (output == expected) ? 1.0 : 0.0
    end

    assert_equal "exact_match", scorer.name
    assert_equal 1.0, scorer.call(input: "apple", expected: "fruit", output: "fruit")
    assert_equal 0.0, scorer.call(input: "apple", expected: "fruit", output: "wrong")
  end

  def test_scorer_with_subset_kwargs_filters_extra_keys
    # Block declares only output: and expected: — no **
    scorer = Braintrust::Scorer.new("subset") do |output:, expected:|
      (output == expected) ? 1.0 : 0.0
    end

    # Calling with extra kwargs (input:, metadata:, tags:) should not raise
    assert_equal 1.0, scorer.call(input: "apple", expected: "fruit", output: "fruit", metadata: {}, tags: ["t1"])
    assert_equal 0.0, scorer.call(input: "apple", expected: "fruit", output: "wrong", metadata: {}, tags: nil)
  end

  def test_scorer_with_legacy_3_param_block
    scorer = Braintrust::Scorer.new("exact_match") do |input, expected, output|
      (output == expected) ? 1.0 : 0.0
    end

    assert_equal "exact_match", scorer.name
    assert_equal 1.0, scorer.call(input: "apple", expected: "fruit", output: "fruit", metadata: {threshold: 0.5})
  end

  def test_scorer_with_legacy_4_param_block
    scorer = Braintrust::Scorer.new("threshold_match") do |input, expected, output, metadata|
      threshold = metadata[:threshold] || 0.8
      score = 0.9
      (score >= threshold) ? 1.0 : 0.0
    end

    assert_equal "threshold_match", scorer.name
    assert_equal 0.0, scorer.call(input: "a", expected: "b", output: "c", metadata: {threshold: 0.95})
    assert_equal 1.0, scorer.call(input: "a", expected: "b", output: "c", metadata: {threshold: 0.85})
  end

  def test_scorer_return_float
    scorer = Braintrust::Scorer.new("float_scorer") { |**| 0.75 }
    assert_equal 0.75, scorer.call(input: "a", expected: "b", output: "c")
  end

  def test_scorer_return_hash
    scorer = Braintrust::Scorer.new("hash_scorer") { |**| {name: "custom_name", score: 0.85} }
    assert_equal({name: "custom_name", score: 0.85}, scorer.call(input: "a", expected: "b", output: "c"))
  end

  def test_scorer_return_array
    scorer = Braintrust::Scorer.new("multi_scorer") do |**|
      [
        {name: "metric1", score: 0.9},
        {name: "metric2", score: 0.8}
      ]
    end

    result = scorer.call(input: "a", expected: "b", output: "c")
    assert_equal 2, result.length
    assert_equal({name: "metric1", score: 0.9}, result[0])
    assert_equal({name: "metric2", score: 0.8}, result[1])
  end

  # ============================================
  # Validation
  # ============================================

  def test_scorer_without_block_or_subclass_raises_on_call
    # Anonymous subclass that doesn't override call and has no block
    klass = Class.new(Braintrust::Scorer)
    scorer = klass.new

    error = assert_raises(NotImplementedError) do
      scorer.call(input: "a", expected: "b", output: "c")
    end

    assert_match(/must provide a block or override #call/i, error.message)
  end

  def test_scorer_invalid_arity_raises
    error = assert_raises(ArgumentError) do
      Braintrust::Scorer.new("bad") { |a, b| a }
    end

    assert_match(/scorer must accept keyword args or 3-4 positional params/i, error.message)
  end

  # ============================================
  # Name detection
  # ============================================

  def test_scorer_name_defaults_to_scorer_for_base_class
    scorer = Braintrust::Scorer.new { |**| 1.0 }
    assert_equal "scorer", scorer.name
  end

  def test_scorer_explicit_name_takes_precedence
    scorer = Braintrust::Scorer.new("my_name") { |**| 1.0 }
    assert_equal "my_name", scorer.name
  end

  # ============================================
  # Subclass pattern
  # ============================================

  def test_subclass_with_call_override
    klass = Class.new(Braintrust::Scorer) do
      def call(output:, expected:, **)
        (output == expected) ? 1.0 : 0.0
      end
    end

    scorer = klass.new
    assert_kind_of Braintrust::Scorer, scorer

    assert_equal 1.0, scorer.call(input: "apple", expected: "fruit", output: "fruit")
    assert_equal 0.0, scorer.call(input: "apple", expected: "fruit", output: "wrong")
  end

  def test_subclass_with_name_override
    klass = Class.new(Braintrust::Scorer) do
      def name
        "custom_name"
      end

      def call(**)
        1.0
      end
    end

    scorer = klass.new
    assert_equal "custom_name", scorer.name
  end

  def test_subclass_name_derived_from_class_name
    klass = Class.new(Braintrust::Scorer) do
      def call(**)
        1.0
      end
    end

    Braintrust.stub_const(:FuzzyMatchTestScorer, klass) do
      scorer = klass.new
      assert_equal "fuzzy_match_test_scorer", scorer.name
    end
  end

  def test_subclass_with_metadata_access
    klass = Class.new(Braintrust::Scorer) do
      def name
        "threshold_scorer"
      end

      def call(output:, expected:, metadata:, **)
        threshold = metadata[:threshold] || 0.8
        if output == expected
          1.0
        else
          ((threshold < 0.5) ? 0.5 : 0.0)
        end
      end
    end

    scorer = klass.new

    assert_equal 1.0, scorer.call(
      input: "a", expected: "b", output: "b",
      metadata: {threshold: 0.9}
    )

    assert_equal 0.5, scorer.call(
      input: "a", expected: "b", output: "c",
      metadata: {threshold: 0.3}
    )
  end

  # ============================================
  # Legacy callable class (not subclassing Scorer)
  # Normalized via Context::Factory
  # ============================================

  def test_legacy_callable_class_normalized_via_factory
    callable = Class.new do
      def name
        "legacy_scorer"
      end

      def call(input, expected, output)
        (output.downcase == expected.downcase) ? 1.0 : 0.0
      end
    end.new

    # Simulate what Factory does
    name = callable.respond_to?(:name) ? callable.name : nil
    scorer = Braintrust::Scorer.new(name, &callable.method(:call))

    assert_equal "legacy_scorer", scorer.name

    # Arity 3 block gets auto-wrapped to kwargs
    assert_equal 1.0, scorer.call(input: "test", expected: "HELLO", output: "hello")
  end

  def test_legacy_callable_class_with_metadata_normalized_via_factory
    callable = Class.new do
      def name
        "legacy_with_meta"
      end

      def call(input, expected, output, metadata = {})
        threshold = metadata[:threshold] || 0.5
        if output == expected
          1.0
        else
          ((threshold < 0.5) ? 0.5 : 0.0)
        end
      end
    end.new

    name = callable.respond_to?(:name) ? callable.name : nil
    scorer = Braintrust::Scorer.new(name, &callable.method(:call))

    assert_equal "legacy_with_meta", scorer.name

    # Arity 4 block gets auto-wrapped to kwargs
    assert_equal 1.0, scorer.call(
      input: "a", expected: "b", output: "b",
      metadata: {threshold: 0.9}
    )
  end
end
