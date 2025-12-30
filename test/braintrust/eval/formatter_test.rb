# frozen_string_literal: true

require "test_helper"
require "braintrust/eval/formatter"
require "braintrust/eval/summary"

class Braintrust::Eval::FormatterTest < Minitest::Test
  def test_colorize_returns_plain_text_when_not_tty
    # When not a TTY, colorize should return plain text
    stub_tty(false) do
      text = Braintrust::Eval::Formatter.colorize("hello", :red)
      assert_equal "hello", text
    end
  end

  def test_colorize_returns_colored_text_when_tty
    # When a TTY, colorize should return colored text
    stub_tty(true) do
      text = Braintrust::Eval::Formatter.colorize("hello", :red)
      assert_equal "\e[31mhello\e[0m", text
    end
  end

  def test_pad_cell_left_align
    # Test left alignment padding
    result = Braintrust::Eval::Formatter.pad_cell("hello", 10, :left)
    assert_equal "hello     ", result
  end

  def test_pad_cell_right_align
    # Test right alignment padding
    result = Braintrust::Eval::Formatter.pad_cell("hello", 10, :right)
    assert_equal "     hello", result
  end

  def test_pad_cell_with_ansi_codes
    # Test that ANSI codes are stripped when calculating visible length
    text_with_ansi = "\e[31mhello\e[0m"
    result = Braintrust::Eval::Formatter.pad_cell(text_with_ansi, 10, :left)
    # Should pad based on visible length (5), not string length
    assert_equal "\e[31mhello\e[0m     ", result
  end

  def test_terminal_link_plain_when_not_tty
    # When not a TTY, terminal_link should return plain text with URL
    stub_tty(false) do
      result = Braintrust::Eval::Formatter.terminal_link("Click here", "https://example.com")
      assert_equal "Click here: https://example.com", result
    end
  end

  def test_terminal_link_osc8_when_tty
    # When a TTY, terminal_link should return OSC 8 hyperlink
    stub_tty(true) do
      result = Braintrust::Eval::Formatter.terminal_link("Click here", "https://example.com")
      assert_equal "\e]8;;https://example.com\e\\Click here\e]8;;\e\\", result
    end
  end

  def test_format_simple_score_row
    # Test formatting a simple score row (no comparison data)
    score = Braintrust::Eval::ScoreSummary.new(name: "exact_match", score: 0.923)
    result = Braintrust::Eval::Formatter.format_simple_score_row(score)

    assert_match(/exact_match/, result)
    assert_match(/92\.3%/, result)
  end

  def test_format_experiment_summary_without_tty
    # Test formatting a complete experiment summary (no TTY - plain text)
    stub_tty(false) do
      summary = Braintrust::Eval::ExperimentSummary.new(
        project_name: "my-project",
        experiment_name: "my-experiment",
        experiment_id: "exp-123",
        experiment_url: "https://braintrust.dev/exp/123",
        scores: {
          "accuracy" => Braintrust::Eval::ScoreSummary.new(name: "accuracy", score: 0.85),
          "relevance" => Braintrust::Eval::ScoreSummary.new(name: "relevance", score: 0.92)
        },
        duration: 1.2345,
        error_count: 0,
        errors: []
      )

      result = Braintrust::Eval::Formatter.format_experiment_summary(summary)

      # Check box structure
      assert_match(/╭─ Experiment summary/, result)
      assert_match(/╰─+╯/, result)

      # Check scores section
      assert_match(/Scores/, result)
      assert_match(/accuracy/, result)
      assert_match(/85\.0%/, result)
      assert_match(/relevance/, result)
      assert_match(/92\.0%/, result)

      # Check link (plain text with URL since not TTY)
      assert_match(/View results for my-experiment/, result)
      assert_match(/https:\/\/braintrust.dev\/exp\/123/, result)
    end
  end

  def test_format_experiment_summary_with_errors
    # Test formatting a summary with errors
    stub_tty(false) do
      summary = Braintrust::Eval::ExperimentSummary.new(
        project_name: "my-project",
        experiment_name: "my-experiment",
        experiment_id: "exp-123",
        experiment_url: "https://braintrust.dev/exp/123",
        scores: {},
        duration: 0.5,
        error_count: 2,
        errors: [
          "Task failed for input 'bad': division by zero",
          "Scorer 'exact' failed: undefined method"
        ]
      )

      result = Braintrust::Eval::Formatter.format_experiment_summary(summary)

      # Check errors section
      assert_match(/Errors/, result)  # Section header
      assert_match(/Task failed for input 'bad'/, result)

      # Should not have Scores section (empty scores)
      refute_match(/Scores/, result)
    end
  end

  def test_format_experiment_summary_empty
    # Test formatting nil summary
    result = Braintrust::Eval::Formatter.format_experiment_summary(nil)
    assert_equal "", result
  end

  def test_format_change_positive
    # Test change formatting for positive values
    stub_tty(false) do
      result = Braintrust::Eval::Formatter.format_change(0.05)  # +5%
      assert_equal "+5.0%", result
    end
  end

  def test_format_change_negative
    # Test change formatting for negative values
    stub_tty(false) do
      result = Braintrust::Eval::Formatter.format_change(-0.1)  # -10%
      assert_equal "-10.0%", result
    end
  end

  def test_format_change_nil
    # Test change formatting for nil values
    stub_tty(false) do
      result = Braintrust::Eval::Formatter.format_change(nil)
      assert_equal "-", result
    end
  end

  def test_format_duration_seconds
    # Test duration formatting for >= 1 second
    result = Braintrust::Eval::Formatter.format_duration(1.2345)
    assert_equal "1.2345s", result

    result = Braintrust::Eval::Formatter.format_duration(10.0)
    assert_equal "10.0s", result
  end

  def test_format_duration_milliseconds
    # Test duration formatting for < 1 second
    result = Braintrust::Eval::Formatter.format_duration(0.123)
    assert_equal "123ms", result

    result = Braintrust::Eval::Formatter.format_duration(0.0018)
    assert_equal "2ms", result

    result = Braintrust::Eval::Formatter.format_duration(0.5)
    assert_equal "500ms", result
  end

  def test_format_error_row
    # Test error row formatting (short message)
    stub_tty(false) do
      result = Braintrust::Eval::Formatter.format_error_row("Task failed: oops")
      assert_equal "✗ Task failed: oops", result
    end
  end

  def test_format_error_row_truncates_long_message
    # Test error row truncates messages over MAX_ERROR_LENGTH
    stub_tty(false) do
      max_len = Braintrust::Eval::Formatter::MAX_ERROR_LENGTH
      # Create a string longer than max_len
      long_error = "x" * (max_len + 20)

      result = Braintrust::Eval::Formatter.format_error_row(long_error)
      # Should be truncated to MAX_ERROR_LENGTH chars with "..."
      assert_equal 2 + max_len, result.length  # "✗ " (2) + MAX_ERROR_LENGTH
      assert result.end_with?("...")
    end
  end

  def test_truncate_error
    # Test truncation helper using the configured MAX_ERROR_LENGTH
    max_len = Braintrust::Eval::Formatter::MAX_ERROR_LENGTH

    # Short strings pass through unchanged
    assert_equal "short", Braintrust::Eval::Formatter.truncate_error("short", max_len)

    # Exact length strings pass through unchanged
    exact_length_str = "x" * max_len
    assert_equal exact_length_str, Braintrust::Eval::Formatter.truncate_error(exact_length_str, max_len)

    # Long strings get truncated to max_len with "..."
    long_str = "x" * (max_len + 10)
    result = Braintrust::Eval::Formatter.truncate_error(long_str, max_len)
    assert_equal max_len, result.length
    assert result.end_with?("...")
  end

  def test_wrap_in_box_without_tty
    # Test box wrapping (no TTY - plain text)
    stub_tty(false) do
      lines = ["Line 1", "Line 2"]
      result = Braintrust::Eval::Formatter.wrap_in_box(lines, "Title")

      assert_match(/╭─ Title/, result)
      assert_match(/Line 1/, result)
      assert_match(/Line 2/, result)
      assert_match(/╰─+╯/, result)
    end
  end

  # Comparison formatting tests
  def test_format_comparison_header
    stub_tty(false) do
      result = Braintrust::Eval::Formatter.format_comparison_header("baseline-exp", "current-exp")
      assert_match(/baseline-exp/, result)
      assert_match(/current-exp/, result)
      assert_match(/baseline/, result)
      assert_match(/comparison/, result)
    end
  end

  def test_format_comparison_score_row
    stub_tty(false) do
      score = Braintrust::Eval::ScoreSummary.new(
        name: "accuracy",
        score: 0.85,
        diff: 0.05,
        improvements: 3,
        regressions: 1
      )

      result = Braintrust::Eval::Formatter.format_comparison_score_row(score)

      assert_match(/accuracy/, result)
      assert_match(/85\.0%/, result)
      assert_match(/\+5\.0%/, result)
      assert_match(/3/, result)
      assert_match(/1/, result)
    end
  end

  def test_format_metric_row
    stub_tty(false) do
      metric = Braintrust::Eval::MetricSummary.new(
        name: "duration",
        metric: 1.25,
        unit: "s",
        diff: -0.1
      )

      result = Braintrust::Eval::Formatter.format_metric_row(metric)

      assert_match(/duration/, result)
      assert_match(/1\.25s/, result)
      assert_match(/-10\.0%/, result)
    end
  end

  def test_format_score_value
    stub_tty(false) do
      # Normal value
      assert_equal "85.0%", Braintrust::Eval::Formatter.format_score_value(0.85)
      # Nil value
      assert_equal "-", Braintrust::Eval::Formatter.format_score_value(nil)
      # 100%
      assert_equal "100.0%", Braintrust::Eval::Formatter.format_score_value(1.0)
      # 0%
      assert_equal "0.0%", Braintrust::Eval::Formatter.format_score_value(0.0)
    end
  end

  def test_format_metric_value
    stub_tty(false) do
      # Normal decimal value
      assert_equal "1.25s", Braintrust::Eval::Formatter.format_metric_value(1.25, "s")
      # Integer value
      assert_equal "150tok", Braintrust::Eval::Formatter.format_metric_value(150.0, "tok")
      # Small value
      assert_equal "0.0012ms", Braintrust::Eval::Formatter.format_metric_value(0.0012, "ms")
      # Nil value
      assert_equal "-", Braintrust::Eval::Formatter.format_metric_value(nil, "s")
    end
  end

  def test_format_count
    stub_tty(false) do
      # Normal count
      assert_equal "5", Braintrust::Eval::Formatter.format_count(5)
      # Zero returns dash
      assert_equal "-", Braintrust::Eval::Formatter.format_count(0)
      # Nil returns dash
      assert_equal "-", Braintrust::Eval::Formatter.format_count(nil)
    end
  end

  def test_has_comparison_data
    # With diff data
    scores_with_diff = {
      "test" => Braintrust::Eval::ScoreSummary.new(name: "test", score: 0.5, diff: 0.1)
    }
    assert Braintrust::Eval::Formatter.has_comparison_data?(scores_with_diff)

    # Without diff data
    scores_without_diff = {
      "test" => Braintrust::Eval::ScoreSummary.new(name: "test", score: 0.5)
    }
    refute Braintrust::Eval::Formatter.has_comparison_data?(scores_without_diff)

    # Empty scores
    refute Braintrust::Eval::Formatter.has_comparison_data?({})

    # Nil scores
    refute Braintrust::Eval::Formatter.has_comparison_data?(nil)
  end

  def test_format_experiment_summary_with_comparison
    stub_tty(false) do
      comparison = Braintrust::Eval::ComparisonInfo.new(
        baseline_experiment_id: "base-123",
        baseline_experiment_name: "baseline-exp"
      )
      scores = {
        "accuracy" => Braintrust::Eval::ScoreSummary.new(
          name: "accuracy",
          score: 0.9,
          diff: 0.05,
          improvements: 2,
          regressions: 1
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

      result = Braintrust::Eval::Formatter.format_experiment_summary(summary)

      # Check comparison header
      assert_match(/baseline-exp.*baseline.*experiment.*comparison/i, result)

      # Check scores section with all columns
      assert_match(/Scores/, result)
      assert_match(/accuracy/, result)
      assert_match(/90\.0%/, result)
      assert_match(/\+5\.0%/, result)

      # Check metrics section
      assert_match(/Metrics/, result)
      assert_match(/duration/, result)
      assert_match(/1\.5s/, result)
      assert_match(/-10\.0%/, result)
    end
  end

  def test_format_scores_table_header
    stub_tty(false) do
      header = Braintrust::Eval::Formatter.format_scores_table_header

      assert_match(/Name/, header)
      assert_match(/Value/, header)
      assert_match(/Change/, header)
      assert_match(/Improvements/, header)
      assert_match(/Regressions/, header)
    end
  end

  def test_format_metrics_table_header
    stub_tty(false) do
      header = Braintrust::Eval::Formatter.format_metrics_table_header

      assert_match(/Name/, header)
      assert_match(/Value/, header)
      assert_match(/Change/, header)
      refute_match(/Improvements/, header)
      refute_match(/Regressions/, header)
    end
  end

  private

  # Helper to stub $stdout.tty? for testing
  def stub_tty(value)
    original_method = $stdout.method(:tty?)
    $stdout.define_singleton_method(:tty?) { value }
    yield
  ensure
    $stdout.define_singleton_method(:tty?, original_method)
  end
end
