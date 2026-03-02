# frozen_string_literal: true

require "test_helper"
require "braintrust/eval/scorer"

class Braintrust::ScorerIdTest < Minitest::Test
  def test_stores_function_id
    scorer_id = Braintrust::ScorerId.new(function_id: "func-123")
    assert_equal "func-123", scorer_id.function_id
  end

  def test_stores_version
    scorer_id = Braintrust::ScorerId.new(function_id: "func-123", version: "v2")
    assert_equal "v2", scorer_id.version
  end

  def test_version_defaults_to_nil
    scorer_id = Braintrust::ScorerId.new(function_id: "func-123")
    assert_nil scorer_id.version
  end

  def test_equality
    a = Braintrust::ScorerId.new(function_id: "func-123", version: "v1")
    b = Braintrust::ScorerId.new(function_id: "func-123", version: "v1")
    assert_equal a, b
  end
end
