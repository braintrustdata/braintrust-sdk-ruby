# frozen_string_literal: true

require "test_helper"
require "braintrust/eval"

class Braintrust::Eval::ScorerTest < Minitest::Test
  def test_new_with_name_and_block_returns_scorer
    scorer = suppress_logs { Braintrust::Eval::Scorer.new("exact_match") { |expected:, output:| (output == expected) ? 1.0 : 0.0 } }
    assert_kind_of Braintrust::Scorer, scorer
    assert_equal "exact_match", scorer.name
  end

  def test_new_with_name_and_callable_returns_scorer
    callable = Class.new {
      def call(expected:, output:)
        (output == expected) ? 1.0 : 0.0
      end
    }.new

    scorer = suppress_logs { Braintrust::Eval::Scorer.new("exact_match", callable) }
    assert_kind_of Braintrust::Scorer, scorer
    assert_equal "exact_match", scorer.name
  end

  def test_new_with_callable_only_returns_scorer
    callable = Class.new {
      def call(expected:, output:)
        (output == expected) ? 1.0 : 0.0
      end
    }.new

    scorer = suppress_logs { Braintrust::Eval::Scorer.new(callable) }
    assert_kind_of Braintrust::Scorer, scorer
  end

  def test_new_logs_deprecation_warning
    assert_warns_once(:eval_scorer_class, /Braintrust::Scorer/) do
      Braintrust::Eval::Scorer.new("test") { |output:| output }
    end
  end

  def test_new_with_keyword_block_multi_score
    scorer = suppress_logs {
      Braintrust::Eval::Scorer.new("multi") do |expected:, output:|
        [
          {name: "exact", score: (output == expected) ? 1.0 : 0.0},
          {name: "nonempty", score: output.to_s.empty? ? 0.0 : 1.0}
        ]
      end
    }
    result = scorer.call(input: "x", expected: "a", output: "a")
    assert_equal [{name: "exact", score: 1.0}, {name: "nonempty", score: 1.0}], result
  end

  def test_new_with_legacy_positional_block
    scorer = suppress_logs { Braintrust::Eval::Scorer.new("legacy") { |i, e, o| (o == e) ? 1.0 : 0.0 } }
    assert_kind_of Braintrust::Scorer, scorer
    assert_equal [{score: 1.0, metadata: nil, name: "legacy"}],
      scorer.call(input: "x", expected: "a", output: "a")
  end

  def test_new_with_legacy_positional_block_multi_score
    scorer = suppress_logs {
      Braintrust::Eval::Scorer.new("legacy_multi") do |i, e, o|
        [
          {name: "exact", score: (o == e) ? 1.0 : 0.0},
          {name: "length", score: (o.length == e.length) ? 1.0 : 0.0}
        ]
      end
    }
    result = scorer.call(input: "x", expected: "hello", output: "world")
    assert_equal [{name: "exact", score: 0.0}, {name: "length", score: 1.0}], result
  end

  # ============================================
  # PositionalArgsRemapping
  # ============================================

  def test_call_with_positional_args
    scorer = suppress_logs { Braintrust::Eval::Scorer.new("legacy") { |i, e, o| (o == e) ? 1.0 : 0.0 } }
    result = suppress_logs { scorer.call("apple", "fruit", "fruit") }
    assert_equal [{score: 1.0, metadata: nil, name: "legacy"}], result
  end

  def test_call_with_positional_args_multi_score
    scorer = suppress_logs {
      Braintrust::Eval::Scorer.new("legacy_multi") do |i, e, o|
        [
          {name: "exact", score: (o == e) ? 1.0 : 0.0},
          {name: "nonempty", score: o.to_s.empty? ? 0.0 : 1.0}
        ]
      end
    }
    result = suppress_logs { scorer.call("x", "fruit", "fruit") }
    assert_equal [{name: "exact", score: 1.0}, {name: "nonempty", score: 1.0}], result
  end

  def test_call_with_positional_args_including_metadata
    scorer = suppress_logs { Braintrust::Eval::Scorer.new("legacy") { |i, e, o, m| m[:boost] ? 1.0 : 0.0 } }
    result = suppress_logs { scorer.call("apple", "fruit", "fruit", {boost: true}) }
    assert_equal [{score: 1.0, metadata: nil, name: "legacy"}], result
  end

  def test_call_with_positional_args_logs_deprecation_warning
    scorer = suppress_logs { Braintrust::Eval::Scorer.new("legacy") { |i, e, o| 1.0 } }
    assert_warns_once(:scorer_positional_call, /keyword args/) do
      scorer.call("a", "b", "c")
    end
  end

  def test_call_with_keyword_args_does_not_trigger_positional_warning
    scorer = suppress_logs { Braintrust::Eval::Scorer.new("kw") { |expected:, output:| (output == expected) ? 1.0 : 0.0 } }
    result = scorer.call(input: "x", expected: "a", output: "a")
    assert_equal [{score: 1.0, metadata: nil, name: "kw"}], result
  end

  # ============================================
  # Eval.scorer module method (deprecated)
  # ============================================

  def test_eval_scorer_method_with_keyword_block
    scorer = suppress_logs { Braintrust::Eval.scorer("kw") { |expected:, output:| (output == expected) ? 1.0 : 0.0 } }
    assert_kind_of Braintrust::Scorer, scorer
    assert_equal "kw", scorer.name
    assert_equal [{score: 1.0, metadata: nil, name: "kw"}],
      scorer.call(input: "x", expected: "a", output: "a")
  end

  def test_eval_scorer_method_with_keyword_block_multi_score
    scorer = suppress_logs {
      Braintrust::Eval.scorer("multi") do |expected:, output:|
        [
          {name: "exact", score: (output == expected) ? 1.0 : 0.0},
          {name: "nonempty", score: output.to_s.empty? ? 0.0 : 1.0}
        ]
      end
    }
    result = scorer.call(input: "x", expected: "a", output: "a")
    assert_equal [{name: "exact", score: 1.0}, {name: "nonempty", score: 1.0}], result
  end

  def test_eval_scorer_method_with_legacy_positional_block
    scorer = suppress_logs { Braintrust::Eval.scorer("legacy") { |i, e, o| (o == e) ? 1.0 : 0.0 } }
    assert_kind_of Braintrust::Scorer, scorer
    assert_equal [{score: 1.0, metadata: nil, name: "legacy"}],
      scorer.call(input: "x", expected: "a", output: "a")
  end

  def test_eval_scorer_method_with_legacy_positional_block_multi_score
    scorer = suppress_logs {
      Braintrust::Eval.scorer("legacy_multi") do |i, e, o|
        [
          {name: "exact", score: (o == e) ? 1.0 : 0.0},
          {name: "length", score: (o.length == e.length) ? 1.0 : 0.0}
        ]
      end
    }
    result = scorer.call(input: "x", expected: "hello", output: "world")
    assert_equal [{name: "exact", score: 0.0}, {name: "length", score: 1.0}], result
  end
end
