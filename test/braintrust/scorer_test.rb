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
    assert_equal [{score: 1.0, metadata: nil, name: "exact_match"}],
      scorer.call(input: "apple", expected: "fruit", output: "fruit")
    assert_equal [{score: 0.0, metadata: nil, name: "exact_match"}],
      scorer.call(input: "apple", expected: "fruit", output: "wrong")
  end

  def test_scorer_with_subset_kwargs_filters_extra_keys
    # Block declares only output: and expected: — no **
    scorer = Braintrust::Scorer.new("subset") do |output:, expected:|
      (output == expected) ? 1.0 : 0.0
    end

    # Calling with extra kwargs (input:, metadata:, tags:) should not raise
    assert_equal [{score: 1.0, metadata: nil, name: "subset"}],
      scorer.call(input: "apple", expected: "fruit", output: "fruit", metadata: {}, tags: ["t1"])
    assert_equal [{score: 0.0, metadata: nil, name: "subset"}],
      scorer.call(input: "apple", expected: "fruit", output: "wrong", metadata: {}, tags: nil)
  end

  def test_scorer_with_legacy_3_param_block
    suppress_logs do
      scorer = Braintrust::Scorer.new("exact_match") do |input, expected, output|
        (output == expected) ? 1.0 : 0.0
      end

      assert_equal "exact_match", scorer.name
      assert_equal [{score: 1.0, metadata: nil, name: "exact_match"}],
        scorer.call(input: "apple", expected: "fruit", output: "fruit", metadata: {threshold: 0.5})
    end
  end

  def test_scorer_with_legacy_3_param_block_multi_score
    suppress_logs do
      scorer = Braintrust::Scorer.new("legacy3") do |input, expected, output|
        [
          {name: "exact", score: (output == expected) ? 1.0 : 0.0},
          {name: "length", score: (output.length == expected.length) ? 1.0 : 0.0}
        ]
      end

      result = scorer.call(input: "x", expected: "fruit", output: "fruit")
      assert_equal [{name: "exact", score: 1.0}, {name: "length", score: 1.0}], result
    end
  end

  def test_scorer_with_legacy_4_param_block
    suppress_logs do
      scorer = Braintrust::Scorer.new("threshold_match") do |input, expected, output, metadata|
        threshold = metadata[:threshold] || 0.8
        score = 0.9
        (score >= threshold) ? 1.0 : 0.0
      end

      assert_equal "threshold_match", scorer.name
      assert_equal [{score: 0.0, metadata: nil, name: "threshold_match"}],
        scorer.call(input: "a", expected: "b", output: "c", metadata: {threshold: 0.95})
      assert_equal [{score: 1.0, metadata: nil, name: "threshold_match"}],
        scorer.call(input: "a", expected: "b", output: "c", metadata: {threshold: 0.85})
    end
  end

  def test_scorer_with_legacy_4_param_block_multi_score
    suppress_logs do
      scorer = Braintrust::Scorer.new("legacy4") do |input, expected, output, metadata|
        threshold = metadata[:threshold] || 0.8
        [
          {name: "match", score: (output == expected) ? 1.0 : 0.0},
          {name: "threshold_met", score: (threshold < 0.9) ? 1.0 : 0.0}
        ]
      end

      result = scorer.call(input: "a", expected: "b", output: "b", metadata: {threshold: 0.5})
      assert_equal [{name: "match", score: 1.0}, {name: "threshold_met", score: 1.0}], result
    end
  end

  def test_scorer_with_keyword_lambda_multi_score
    # Bare lambda passed through Factory (Proc branch -> Scorer.new(&scorer))
    lam = ->(expected:, output:) {
      [
        {name: "exact", score: (output == expected) ? 1.0 : 0.0},
        {name: "length", score: (output.length == expected.length) ? 1.0 : 0.0}
      ]
    }
    scorer = Braintrust::Scorer.new(&lam)

    result = scorer.call(input: "x", expected: "hello", output: "world")
    assert_equal [{name: "exact", score: 0.0}, {name: "length", score: 1.0}], result
  end

  def test_scorer_return_float
    scorer = Braintrust::Scorer.new("float_scorer") { |**| 0.75 }
    assert_equal [{score: 0.75, metadata: nil, name: "float_scorer"}],
      scorer.call(input: "a", expected: "b", output: "c")
  end

  def test_scorer_return_hash
    scorer = Braintrust::Scorer.new("hash_scorer") { |**| {name: "custom_name", score: 0.85} }
    assert_equal [{name: "custom_name", score: 0.85}],
      scorer.call(input: "a", expected: "b", output: "c")
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

  def test_scorer_without_block_or_override_raises_on_call
    klass = Class.new do
      include Braintrust::Scorer
    end
    scorer = klass.new

    assert_raises(NoMethodError) do
      scorer.call(input: "a", expected: "b", output: "c")
    end
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
    klass = Class.new do
      include Braintrust::Scorer

      def call(output:, expected:)
        (output == expected) ? 1.0 : 0.0
      end
    end

    scorer = klass.new
    assert_kind_of Braintrust::Scorer, scorer

    assert_equal [{score: 1.0, metadata: nil, name: "scorer"}],
      scorer.call(input: "apple", expected: "fruit", output: "fruit")
    assert_equal [{score: 0.0, metadata: nil, name: "scorer"}],
      scorer.call(input: "apple", expected: "fruit", output: "wrong")
  end

  def test_subclass_with_call_override_multi_score
    klass = Class.new do
      include Braintrust::Scorer

      def name
        "multi_subclass"
      end

      def call(output:, expected:)
        [
          {name: "exact", score: (output == expected) ? 1.0 : 0.0},
          {name: "nonempty", score: output.to_s.empty? ? 0.0 : 1.0}
        ]
      end
    end

    scorer = klass.new
    result = scorer.call(input: "x", expected: "fruit", output: "fruit")
    assert_equal [{name: "exact", score: 1.0}, {name: "nonempty", score: 1.0}], result

    result2 = scorer.call(input: "x", expected: "fruit", output: "wrong")
    assert_equal [{name: "exact", score: 0.0}, {name: "nonempty", score: 1.0}], result2
  end

  def test_subclass_with_name_override
    klass = Class.new do
      include Braintrust::Scorer

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
    klass = Class.new do
      include Braintrust::Scorer

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
    klass = Class.new do
      include Braintrust::Scorer

      def name
        "threshold_scorer"
      end

      def call(output:, expected:, metadata:)
        threshold = metadata[:threshold] || 0.8
        if output == expected
          1.0
        else
          ((threshold < 0.5) ? 0.5 : 0.0)
        end
      end
    end

    scorer = klass.new

    assert_equal [{score: 1.0, metadata: nil, name: "threshold_scorer"}],
      scorer.call(input: "a", expected: "b", output: "b", metadata: {threshold: 0.9})
    assert_equal [{score: 0.5, metadata: nil, name: "threshold_scorer"}],
      scorer.call(input: "a", expected: "b", output: "c", metadata: {threshold: 0.3})
  end

  # ============================================
  # Legacy callable class (not subclassing Scorer)
  # Normalized via Context::Factory
  # ============================================

  def test_legacy_callable_class_normalized_via_factory
    suppress_logs do
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
      assert_equal [{score: 1.0, metadata: nil, name: "legacy_scorer"}],
        scorer.call(input: "test", expected: "HELLO", output: "hello")
    end
  end

  def test_legacy_callable_class_multi_score_normalized_via_factory
    suppress_logs do
      callable = Class.new do
        def name
          "legacy_multi"
        end

        def call(input, expected, output)
          [
            {name: "exact", score: (output == expected) ? 1.0 : 0.0},
            {name: "case_insensitive", score: (output.downcase == expected.downcase) ? 1.0 : 0.0}
          ]
        end
      end.new

      name = callable.respond_to?(:name) ? callable.name : nil
      scorer = Braintrust::Scorer.new(name, &callable.method(:call))

      assert_equal "legacy_multi", scorer.name
      result = scorer.call(input: "test", expected: "HELLO", output: "hello")
      assert_equal [{name: "exact", score: 0.0}, {name: "case_insensitive", score: 1.0}], result
    end
  end

  def test_legacy_callable_class_with_metadata_normalized_via_factory
    suppress_logs do
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
      assert_equal [{score: 1.0, metadata: nil, name: "legacy_with_meta"}],
        scorer.call(input: "a", expected: "b", output: "b", metadata: {threshold: 0.9})
    end
  end

  # ============================================
  # Scorer::ID
  # ============================================

  def test_id_stores_function_id
    scorer_id = Braintrust::Scorer::ID.new(function_id: "func-123")
    assert_equal "func-123", scorer_id.function_id
  end

  def test_id_stores_version
    scorer_id = Braintrust::Scorer::ID.new(function_id: "func-123", version: "v2")
    assert_equal "v2", scorer_id.version
  end

  def test_id_version_defaults_to_nil
    scorer_id = Braintrust::Scorer::ID.new(function_id: "func-123")
    assert_nil scorer_id.version
  end

  def test_id_equality
    a = Braintrust::Scorer::ID.new(function_id: "func-123", version: "v1")
    b = Braintrust::Scorer::ID.new(function_id: "func-123", version: "v1")
    assert_equal a, b
  end
end
