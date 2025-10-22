# frozen_string_literal: true

require "test_helper"
require "braintrust/eval/result"

class Braintrust::Eval::ResultTest < Minitest::Test
  def test_result_with_success
    # Test successful result (no errors)
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "my-experiment",
      project_id: "proj_456",
      permalink: "https://braintrust.dev/link",
      errors: [],
      duration: 1.5
    )

    assert_equal "exp_123", result.experiment_id
    assert_equal "my-experiment", result.experiment_name
    assert_equal "proj_456", result.project_id
    assert_equal "https://braintrust.dev/link", result.permalink
    assert_equal [], result.errors
    assert_equal 1.5, result.duration

    assert result.success?
    refute result.failed?
  end

  def test_result_with_errors
    # Test failed result (with errors)
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "my-experiment",
      project_id: "proj_456",
      permalink: "https://braintrust.dev/link",
      errors: ["Task failed for input 'apple'", "Scorer 'exact_match' failed"],
      duration: 2.3
    )

    assert_equal 2, result.errors.length
    refute result.success?
    assert result.failed?
  end

  def test_result_to_s_success
    # Test to_s formatting for successful result
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "food-classifier",
      project_id: "proj_456",
      permalink: "https://braintrust.dev/link",
      errors: [],
      duration: 1.234
    )

    output = result.to_s

    assert_match(/food-classifier/, output)
    assert_match(/proj_456/, output)
    assert_match(/1.2s/, output)  # Rounded to 1 decimal
    assert_match(/braintrust.dev\/link/, output)
    refute_match(/Errors:/, output)  # No errors section
  end

  def test_result_to_s_with_errors
    # Test to_s formatting for failed result
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "food-classifier",
      project_id: "proj_456",
      permalink: "https://braintrust.dev/link",
      errors: ["Error 1", "Error 2"],
      duration: 1.234
    )

    output = result.to_s

    assert_match(/food-classifier/, output)
    assert_match(/Errors:/, output)
    assert_match(/Error 1/, output)
    assert_match(/Error 2/, output)
  end

  def test_result_requires_all_fields
    # Test that all required fields must be provided
    assert_raises(ArgumentError) do
      Braintrust::Eval::Result.new(
        experiment_name: "test"
        # Missing other required fields
      )
    end
  end
end
