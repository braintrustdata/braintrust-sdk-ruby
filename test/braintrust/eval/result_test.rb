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
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: [],
      duration: 1.5
    )

    assert_equal "exp_123", result.experiment_id
    assert_equal "my-experiment", result.experiment_name
    assert_equal "proj_456", result.project_id
    assert_equal "my-project", result.project_name
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
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: ["Task failed for input 'apple'", "Scorer 'exact_match' failed"],
      duration: 2.3
    )

    assert_equal 2, result.errors.length
    refute result.success?
    assert result.failed?
  end

  def test_result_to_s_success
    # Test to_s formatting for successful result (Go SDK format)
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "food-classifier",
      project_id: "proj_456",
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: [],
      duration: 1.234
    )

    output = result.to_s

    assert_match(/Experiment: food-classifier/, output)
    assert_match(/Project: my-project/, output)
    assert_match(/ID: exp_123/, output)
    assert_match(/Link: https:\/\/braintrust.dev\/link/, output)
    assert_match(/Duration: 1.234/, output)  # Rounded to 4 decimals
    assert_match(/Errors: 0/, output)
  end

  def test_result_to_s_with_errors
    # Test to_s formatting for failed result (Go SDK format)
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "food-classifier",
      project_id: "proj_456",
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: ["Error 1", "Error 2"],
      duration: 1.234
    )

    output = result.to_s

    assert_match(/Experiment: food-classifier/, output)
    assert_match(/Project: my-project/, output)
    assert_match(/ID: exp_123/, output)
    assert_match(/Errors: 2/, output)  # Shows count, not details
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

  def test_summary_scores_computes_mean
    # Test that summary scores computes mean from raw scores
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "my-experiment",
      project_id: "proj_456",
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: [],
      duration: 1.5,
      scores: {
        "exact_match" => [1.0, 0.0, 1.0, 1.0],  # mean = 0.75
        "relevance" => [0.8, 0.9, 0.7]           # mean = 0.8
      }
    )

    scores = result.summary.scores

    assert_equal 2, scores.size
    assert_equal "exact_match", scores["exact_match"].name
    assert_equal 0.75, scores["exact_match"].score
    assert_equal "relevance", scores["relevance"].name
    assert_in_delta 0.8, scores["relevance"].score, 0.001
  end

  def test_summary_scores_empty_when_no_scores
    # Test summary.scores returns empty hash when no score data
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "my-experiment",
      project_id: "proj_456",
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: [],
      duration: 1.5
    )

    assert_equal({}, result.summary.scores)
  end

  def test_summary_builds_from_scores
    # Test that summary is lazily built from score data
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "my-experiment",
      project_id: "proj_456",
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: [],
      duration: 1.5,
      scores: {
        "exact_match" => [1.0, 0.0, 1.0]
      }
    )

    summary = result.summary

    assert_instance_of Braintrust::Eval::ExperimentSummary, summary
    assert_equal "my-project", summary.project_name
    assert_equal "my-experiment", summary.experiment_name
    assert_equal "exp_123", summary.experiment_id
    assert_equal "https://braintrust.dev/link", summary.experiment_url
    assert_equal 1, summary.scores.size
    assert_in_delta 0.6667, summary.scores["exact_match"].score, 0.001
    assert_equal 1.5, summary.duration
    assert_equal 0, summary.error_count
    assert_equal [], summary.errors
  end

  def test_summary_includes_errors
    # Test that summary includes error information
    errors = ["Task failed: Error 1", "Scorer failed: Error 2"]

    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "my-experiment",
      project_id: "proj_456",
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: errors,
      duration: 1.5
    )

    summary = result.summary

    assert_equal 2, summary.error_count
    assert_equal errors, summary.errors
  end

  def test_summary_without_scores
    # Test that summary is still created when no score data (for metadata display)
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "my-experiment",
      project_id: "proj_456",
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: [],
      duration: 1.5
    )

    summary = result.summary

    assert_instance_of Braintrust::Eval::ExperimentSummary, summary
    assert_equal "my-experiment", summary.experiment_name
    assert_equal({}, summary.scores)
  end

  def test_to_pretty_with_scores
    # Test to_pretty formats summary (without TTY colors)
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "my-experiment",
      project_id: "proj_456",
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: [],
      duration: 1.5,
      scores: {
        "exact_match" => [0.75, 0.75, 0.75]
      }
    )

    output = result.to_pretty

    assert_match(/Experiment summary/, output)
    assert_match(/exact_match/, output)
    assert_match(/75\.0%/, output)
    assert_match(/View results for my-experiment/, output)
  end

  def test_to_pretty_without_scores
    # Test to_pretty still works when no score data (shows link only)
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "my-experiment",
      project_id: "proj_456",
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: [],
      duration: 1.5
    )

    output = result.to_pretty

    assert_match(/Experiment summary/, output)
    assert_match(/View results for my-experiment/, output)
    # Should not have Scores section
    refute_match(/Scores/, output)
  end

  def test_to_pretty_with_errors
    # Test to_pretty shows error section when there are errors
    result = Braintrust::Eval::Result.new(
      experiment_id: "exp_123",
      experiment_name: "my-experiment",
      project_id: "proj_456",
      project_name: "my-project",
      permalink: "https://braintrust.dev/link",
      errors: ["Task failed for input 'bad': division by zero"],
      duration: 1.5
    )

    output = result.to_pretty

    assert_match(/Errors/, output)  # Errors section header
    assert_match(/Task failed for input 'bad'/, output)
  end
end
