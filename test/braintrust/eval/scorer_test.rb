# frozen_string_literal: true

require "test_helper"
require "braintrust/eval/scorer"

class Braintrust::Eval::ScorerTest < Minitest::Test
  def test_scorer_with_3_param_block
    # Test scorer with 3 params (input, expected, output)
    # Block should be called without metadata
    scorer = Braintrust::Eval::Scorer.new("exact_match") do |input, expected, output|
      (output == expected) ? 1.0 : 0.0
    end

    assert_equal "exact_match", scorer.name

    # Call with metadata - block should ignore it
    result = scorer.call("apple", "fruit", "fruit", {threshold: 0.5})
    assert_equal 1.0, result
  end

  def test_scorer_with_4_param_block
    # Test scorer with 4 params (input, expected, output, metadata)
    # Block should receive metadata
    scorer = Braintrust::Eval::Scorer.new("threshold_match") do |input, expected, output, metadata|
      threshold = metadata[:threshold] || 0.8
      score = 0.9
      (score >= threshold) ? 1.0 : 0.0
    end

    assert_equal "threshold_match", scorer.name

    # Call with high threshold - should fail
    result = scorer.call("a", "b", "c", {threshold: 0.95})
    assert_equal 0.0, result

    # Call with low threshold - should pass
    result = scorer.call("a", "b", "c", {threshold: 0.85})
    assert_equal 1.0, result
  end

  def test_scorer_with_callable_object
    # Test scorer with object that responds to .call
    callable = Class.new do
      def call(input, expected, output)
        (output.downcase == expected.downcase) ? 1.0 : 0.0
      end
    end.new

    scorer = Braintrust::Eval::Scorer.new("case_insensitive", callable)

    assert_equal "case_insensitive", scorer.name

    result = scorer.call("test", "HELLO", "hello", {})
    assert_equal 1.0, result
  end

  def test_scorer_return_float
    # Test that float return values are passed through
    scorer = Braintrust::Eval::Scorer.new("float_scorer") do |i, e, o|
      0.75
    end

    result = scorer.call("a", "b", "c", {})
    assert_equal 0.75, result
  end

  def test_scorer_return_hash
    # Test that hash return values are normalized
    scorer = Braintrust::Eval::Scorer.new("hash_scorer") do |i, e, o|
      {name: "custom_name", score: 0.85}
    end

    result = scorer.call("a", "b", "c", {})
    assert_equal({name: "custom_name", score: 0.85}, result)
  end

  def test_scorer_return_array
    # Test that array return values are normalized
    scorer = Braintrust::Eval::Scorer.new("multi_scorer") do |i, e, o|
      [
        {name: "metric1", score: 0.9},
        {name: "metric2", score: 0.8}
      ]
    end

    result = scorer.call("a", "b", "c", {})
    assert_equal 2, result.length
    assert_equal({name: "metric1", score: 0.9}, result[0])
    assert_equal({name: "metric2", score: 0.8}, result[1])
  end

  def test_scorer_invalid_arity
    # Test that scorer raises error for invalid arity
    error = assert_raises(ArgumentError) do
      Braintrust::Eval::Scorer.new("bad_scorer") do |only_one_param|
        1.0
      end
    end

    assert_match(/must accept 3 or 4 parameters/, error.message)
  end

  def test_scorer_missing_callable
    # Test that scorer raises error if no callable provided
    error = assert_raises(ArgumentError) do
      Braintrust::Eval::Scorer.new("no_callable")
    end

    assert_match(/must provide callable or block/i, error.message)
  end

  def test_scorer_with_callable_object_having_name
    # Test scorer that uses object's .name method if available
    callable = Class.new do
      def name
        "object_name"
      end

      def call(input, expected, output)
        1.0
      end
    end.new

    # When name is provided explicitly, it should override object's name
    scorer = Braintrust::Eval::Scorer.new("explicit_name", callable)
    assert_equal "explicit_name", scorer.name
  end

  def test_scorer_with_method_auto_name
    # Test that method objects automatically use the method name
    sample_scorer = lambda { |input, expected, output|
      (output == expected) ? 1.0 : 0.0
    }
    # Give it a name property for testing
    sample_scorer.define_singleton_method(:name) { "sample_scorer" }

    # Pass method object without explicit name
    scorer = Braintrust::Eval::Scorer.new(sample_scorer)

    # Should auto-detect name from method
    assert_equal "sample_scorer", scorer.name

    result = scorer.call("test", "fruit", "fruit", {})
    assert_equal 1.0, result
  end

  def test_scorer_with_callable_object_auto_name
    # Test that objects with .name method automatically use it
    callable = Class.new do
      def name
        "auto_name"
      end

      def call(input, expected, output)
        1.0
      end
    end.new

    # Pass callable without explicit name
    scorer = Braintrust::Eval::Scorer.new(callable)

    # Should auto-detect name from object
    assert_equal "auto_name", scorer.name
  end

  def test_scorer_with_method_object
    # Test Method object name detection (is_a?(Method) branch)
    obj = Object.new
    def obj.my_scorer(input, expected, output)
      (output == expected) ? 1.0 : 0.0
    end

    method_obj = obj.method(:my_scorer)
    scorer = Braintrust::Eval::Scorer.new(method_obj)

    assert_equal "my_scorer", scorer.name
    assert_equal 1.0, scorer.call("i", "match", "match")
    assert_equal 0.0, scorer.call("i", "match", "no_match")
  end
end
