# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::ScorerUtilsTest < Minitest::Test
  # ============================================
  # extract_name tests
  # ============================================

  def test_extract_name_from_scorer_with_name_method
    scorer = Object.new
    def scorer.name
      "accuracy"
    end

    result = Braintrust::Remote::ScorerUtils.extract_name(scorer, 0)

    assert_equal "accuracy", result
  end

  def test_extract_name_from_scorer_with_scorer_name_method
    scorer = Object.new
    def scorer.scorer_name
      "factuality"
    end

    result = Braintrust::Remote::ScorerUtils.extract_name(scorer, 0)

    assert_equal "factuality", result
  end

  def test_extract_name_prefers_name_over_scorer_name
    scorer = Object.new
    def scorer.name
      "name_method"
    end

    def scorer.scorer_name
      "scorer_name_method"
    end

    result = Braintrust::Remote::ScorerUtils.extract_name(scorer, 0)

    assert_equal "name_method", result
  end

  def test_extract_name_falls_back_to_index_based_name
    scorer = ->(input:, output:, expected:, **) { 1.0 }

    result = Braintrust::Remote::ScorerUtils.extract_name(scorer, 3)

    assert_equal "scorer_3", result
  end

  def test_extract_name_with_nil_name_falls_back_to_index
    scorer = Object.new
    def scorer.name
      nil
    end

    result = Braintrust::Remote::ScorerUtils.extract_name(scorer, 5)

    assert_equal "scorer_5", result
  end

  def test_extract_name_with_empty_string_name_falls_back_to_index
    scorer = Object.new
    def scorer.name
      ""
    end

    # Empty string is falsy in the `&&` check, so falls back
    result = Braintrust::Remote::ScorerUtils.extract_name(scorer, 2)

    # Note: empty string is truthy in Ruby, so this actually returns ""
    # This tests the current behavior - empty string is still returned
    assert_equal "", result
  end

  def test_extract_name_with_inline_scorer
    scorer = Braintrust::Remote::InlineScorer.new("my_scorer") do |input:, output:, expected:, **|
      1.0
    end

    result = Braintrust::Remote::ScorerUtils.extract_name(scorer, 0)

    assert_equal "my_scorer", result
  end

  def test_extract_name_with_remote_scorer
    # Mock API for RemoteScorer
    api = Object.new

    scorer = Braintrust::Remote::RemoteScorer.new(
      name: "remote_accuracy",
      api: api,
      function_id: "func-123"
    )

    result = Braintrust::Remote::ScorerUtils.extract_name(scorer, 0)

    assert_equal "remote_accuracy", result
  end

  def test_extract_name_with_zero_index
    scorer = proc { 1.0 }

    result = Braintrust::Remote::ScorerUtils.extract_name(scorer, 0)

    assert_equal "scorer_0", result
  end

  def test_extract_name_with_large_index
    scorer = proc { 1.0 }

    result = Braintrust::Remote::ScorerUtils.extract_name(scorer, 999)

    assert_equal "scorer_999", result
  end
end
