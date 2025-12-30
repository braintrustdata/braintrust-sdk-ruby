# frozen_string_literal: true

require "test_helper"
require "braintrust/eval/summary"

class Braintrust::Eval::SummaryTest < Minitest::Test
  # ScoreSummary tests
  def test_score_summary_struct_fields
    score = Braintrust::Eval::ScoreSummary.new(
      name: "accuracy",
      score: 0.85,
      diff: 0.05,
      improvements: 3,
      regressions: 1
    )

    assert_equal "accuracy", score.name
    assert_equal 0.85, score.score
    assert_equal 0.05, score.diff
    assert_equal 3, score.improvements
    assert_equal 1, score.regressions
  end

  def test_score_summary_from_values_computes_mean
    score = Braintrust::Eval::ScoreSummary.from_values("test", [1.0, 0.5, 0.8])

    assert_equal "test", score.name
    assert_in_delta 0.7667, score.score, 0.001
    assert_nil score.diff
    assert_nil score.improvements
    assert_nil score.regressions
  end

  def test_score_summary_from_values_handles_empty_array
    score = Braintrust::Eval::ScoreSummary.from_values("test", [])

    assert_equal "test", score.name
    assert_equal 0.0, score.score
  end

  def test_score_summary_from_values_with_single_value
    score = Braintrust::Eval::ScoreSummary.from_values("test", [0.9])

    assert_equal "test", score.name
    assert_equal 0.9, score.score
  end

  def test_score_summary_optional_fields_nil_by_default
    score = Braintrust::Eval::ScoreSummary.new(name: "test", score: 0.5)

    assert_equal "test", score.name
    assert_equal 0.5, score.score
    assert_nil score.diff
    assert_nil score.improvements
    assert_nil score.regressions
  end

  # MetricSummary tests
  def test_metric_summary_struct_fields
    metric = Braintrust::Eval::MetricSummary.new(
      name: "duration",
      metric: 1.25,
      unit: "s",
      diff: -0.05
    )

    assert_equal "duration", metric.name
    assert_equal 1.25, metric.metric
    assert_equal "s", metric.unit
    assert_equal(-0.05, metric.diff)
  end

  def test_metric_summary_with_nil_diff
    metric = Braintrust::Eval::MetricSummary.new(
      name: "tokens",
      metric: 150,
      unit: "tok"
    )

    assert_equal "tokens", metric.name
    assert_equal 150, metric.metric
    assert_equal "tok", metric.unit
    assert_nil metric.diff
  end

  # ComparisonInfo tests
  def test_comparison_info_struct_fields
    comparison = Braintrust::Eval::ComparisonInfo.new(
      baseline_experiment_id: "base-123",
      baseline_experiment_name: "baseline-exp"
    )

    assert_equal "base-123", comparison.baseline_experiment_id
    assert_equal "baseline-exp", comparison.baseline_experiment_name
  end

  # ExperimentSummary tests
  def test_experiment_summary_struct_fields
    summary = Braintrust::Eval::ExperimentSummary.new(
      project_name: "my-project",
      experiment_name: "my-experiment",
      experiment_id: "exp-123",
      experiment_url: "https://example.com/exp/123",
      scores: {},
      metrics: {},
      comparison: nil,
      duration: 1.5,
      error_count: 0,
      errors: []
    )

    assert_equal "my-project", summary.project_name
    assert_equal "my-experiment", summary.experiment_name
    assert_equal "exp-123", summary.experiment_id
    assert_equal "https://example.com/exp/123", summary.experiment_url
    assert_equal({}, summary.scores)
    assert_equal({}, summary.metrics)
    assert_nil summary.comparison
    assert_equal 1.5, summary.duration
    assert_equal 0, summary.error_count
    assert_equal [], summary.errors
  end

  def test_experiment_summary_from_scores
    raw_scores = {
      "accuracy" => [0.9, 0.8, 0.85],
      "relevance" => [1.0, 0.5]
    }
    metadata = {
      project_name: "test-project",
      experiment_name: "test-exp",
      experiment_id: "exp-456",
      experiment_url: "https://example.com",
      duration: 2.0,
      error_count: 0,
      errors: []
    }

    summary = Braintrust::Eval::ExperimentSummary.from_raw_scores(raw_scores, metadata)

    assert_equal "test-project", summary.project_name
    assert_equal "test-exp", summary.experiment_name
    assert_equal 2, summary.scores.size
    assert_in_delta 0.85, summary.scores["accuracy"].score, 0.001
    assert_in_delta 0.75, summary.scores["relevance"].score, 0.001
    assert_nil summary.metrics
    assert_nil summary.comparison
  end

  def test_experiment_summary_from_scores_with_symbol_keys
    raw_scores = {
      accuracy: [0.9, 0.8],
      relevance: [1.0]
    }
    metadata = {
      project_name: "test",
      experiment_name: "test",
      experiment_id: nil,
      experiment_url: nil,
      duration: 1.0,
      error_count: 0,
      errors: []
    }

    summary = Braintrust::Eval::ExperimentSummary.from_raw_scores(raw_scores, metadata)

    # Keys should be converted to strings
    assert_equal 2, summary.scores.size
    assert summary.scores.key?("accuracy")
    assert summary.scores.key?("relevance")
  end

  def test_experiment_summary_from_scores_with_nil_scores
    metadata = {
      project_name: "test",
      experiment_name: "test",
      experiment_id: nil,
      experiment_url: nil,
      duration: 1.0,
      error_count: 0,
      errors: []
    }

    summary = Braintrust::Eval::ExperimentSummary.from_raw_scores(nil, metadata)

    assert_equal({}, summary.scores)
  end

  def test_experiment_summary_with_comparison
    comparison = Braintrust::Eval::ComparisonInfo.new(
      baseline_experiment_id: "base-123",
      baseline_experiment_name: "baseline"
    )
    scores = {
      "accuracy" => Braintrust::Eval::ScoreSummary.new(
        name: "accuracy",
        score: 0.9,
        diff: 0.05,
        improvements: 2,
        regressions: 0
      )
    }
    metrics = {
      "duration" => Braintrust::Eval::MetricSummary.new(
        name: "duration",
        metric: 1.5,
        unit: "s",
        diff: -0.1
      )
    }

    summary = Braintrust::Eval::ExperimentSummary.new(
      project_name: "project",
      experiment_name: "experiment",
      experiment_id: "exp-789",
      experiment_url: "https://example.com",
      scores: scores,
      metrics: metrics,
      comparison: comparison,
      duration: 10.0,
      error_count: 0,
      errors: []
    )

    assert_equal "baseline", summary.comparison.baseline_experiment_name
    assert_equal 1, summary.scores.size
    assert_equal 1, summary.metrics.size
    assert_equal 0.05, summary.scores["accuracy"].diff
    assert_equal(-0.1, summary.metrics["duration"].diff)
  end
end
