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

  def test_format_score_row
    # Test formatting a score row
    score = Braintrust::Eval::ScorerStats.new(name: "exact_match", score_mean: 0.923)
    result = Braintrust::Eval::Formatter.format_score_row(score)

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
          "accuracy" => Braintrust::Eval::ScorerStats.new(name: "accuracy", score_mean: 0.85),
          "relevance" => Braintrust::Eval::ScorerStats.new(name: "relevance", score_mean: 0.92)
        },
        duration: 1.2345,
        error_count: 0,
        errors: []
      )

      result = Braintrust::Eval::Formatter.format_experiment_summary(summary)

      # Check box structure
      assert_match(/╭─ Experiment summary/, result)
      assert_match(/╰─+╯/, result)

      # Check metadata
      assert_match(/Experiment:.*my-experiment/, result)
      assert_match(/Project:.*my-project/, result)
      assert_match(/ID:.*exp-123/, result)
      assert_match(/Duration:.*1\.2345s/, result)  # >= 1s shows as seconds
      assert_match(/Errors:.*0/, result)

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
    # Test formatting a summary with errors (also tests millisecond duration)
    stub_tty(false) do
      summary = Braintrust::Eval::ExperimentSummary.new(
        project_name: "my-project",
        experiment_name: "my-experiment",
        experiment_id: "exp-123",
        experiment_url: "https://braintrust.dev/exp/123",
        scores: {},
        duration: 0.5,  # < 1s, should display as 500ms
        error_count: 2,
        errors: [
          "Task failed for input 'bad': division by zero",
          "Scorer 'exact' failed: undefined method"
        ]
      )

      result = Braintrust::Eval::Formatter.format_experiment_summary(summary)

      # Check metadata shows error count and millisecond duration
      assert_match(/Duration:.*500ms/, result)
      assert_match(/Errors:.*2/, result)

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

  def test_format_metadata_row
    # Test metadata row formatting
    stub_tty(false) do
      result = Braintrust::Eval::Formatter.format_metadata_row("Label", "value")
      assert_equal "Label: value", result
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
