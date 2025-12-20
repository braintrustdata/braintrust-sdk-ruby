# frozen_string_literal: true

module Braintrust
  module Eval
    # Formatter for pretty CLI output of experiment results
    # Uses ANSI colors and Unicode box drawing for terminal display
    module Formatter
      # ANSI color codes
      COLORS = {
        gray: "\e[90m",
        red: "\e[31m",
        green: "\e[32m",
        blue: "\e[34m",
        magenta: "\e[35m",
        white: "\e[97m",
        dim: "\e[2m",
        reset: "\e[0m"
      }.freeze

      # Box drawing characters (Unicode)
      BOX = {
        top_left: "╭",
        top_right: "╮",
        bottom_left: "╰",
        bottom_right: "╯",
        horizontal: "─",
        vertical: "│"
      }.freeze

      # Maximum length for error messages before truncation
      MAX_ERROR_LENGTH = 150

      # Column widths for comparison table
      COLUMN_WIDTHS = {
        name: 22,
        value: 12,
        change: 10,
        improvements: 14,
        regressions: 12
      }.freeze

      class << self
        # Format an experiment summary for CLI output
        # @param summary [ExperimentSummary] The experiment summary
        # @return [String] Formatted output with box drawing and colors
        def format_experiment_summary(summary)
          return "" unless summary

          lines = []

          # Comparison header (if comparing)
          if summary.comparison&.baseline_experiment_name
            lines << format_comparison_header(
              summary.comparison.baseline_experiment_name,
              summary.experiment_name
            )
            lines << ""
          end

          # Scores section
          if summary.scores&.any?
            lines << colorize("Scores", :white)

            if has_comparison_data?(summary.scores)
              lines << format_scores_table_header
              summary.scores.each_value do |score|
                lines << format_comparison_score_row(score)
              end
            else
              # Simple format without comparison columns
              max_name_len = summary.scores.values.map { |s| s.name.length }.max || 0
              name_width = [max_name_len + 2, 20].max
              summary.scores.each_value do |score|
                lines << format_simple_score_row(score, name_width)
              end
            end
          end

          # Metrics section (only if present - comparison mode)
          if summary.metrics&.any?
            lines << ""
            lines << colorize("Metrics", :white)
            lines << format_metrics_table_header
            summary.metrics.each_value do |metric|
              lines << format_metric_row(metric)
            end
          end

          # Errors section (if any)
          if summary.errors&.any?
            lines << ""
            lines << colorize("Errors", :white)
            summary.errors.each do |error|
              lines << format_error_row(error)
            end
          end

          # Footer link
          if summary.experiment_url
            lines << ""
            lines << terminal_link("View results for #{summary.experiment_name}", summary.experiment_url)
          end

          wrap_in_box(lines, "Experiment summary")
        end

        # Format comparison header line
        # @param baseline [String] Baseline experiment name
        # @param comparison [String] Comparison (current) experiment name
        # @return [String] Formatted header
        def format_comparison_header(baseline, comparison)
          "#{baseline} (baseline) #{colorize("←", :gray)} #{comparison} (comparison)"
        end

        # Format table header for scores section (5 columns)
        # @return [String] Header row
        def format_scores_table_header
          name = pad_cell("Name", COLUMN_WIDTHS[:name], :left)
          value = pad_cell("Value", COLUMN_WIDTHS[:value], :right)
          change = pad_cell("Change", COLUMN_WIDTHS[:change], :right)
          improvements = pad_cell("Improvements", COLUMN_WIDTHS[:improvements], :right)
          regressions = pad_cell("Regressions", COLUMN_WIDTHS[:regressions], :right)
          colorize("#{name}#{value}#{change}#{improvements}#{regressions}", :dim)
        end

        # Format table header for metrics section (3 columns)
        # @return [String] Header row
        def format_metrics_table_header
          name = pad_cell("Name", COLUMN_WIDTHS[:name], :left)
          value = pad_cell("Value", COLUMN_WIDTHS[:value], :right)
          change = pad_cell("Change", COLUMN_WIDTHS[:change], :right)
          colorize("#{name}#{value}#{change}", :dim)
        end

        # Format a score row with all comparison columns (5 columns)
        # @param score [ScoreSummary] The score summary
        # @return [String] Formatted row
        def format_comparison_score_row(score)
          name = "#{colorize("◯", :blue)} #{score.name}"
          value = format_score_value(score.score)
          change = format_change(score.diff)
          improvements = format_count(score.improvements, :green)
          regressions = format_count(score.regressions, :red)

          pad_cell(name, COLUMN_WIDTHS[:name], :left) +
            pad_cell(value, COLUMN_WIDTHS[:value], :right) +
            pad_cell(change, COLUMN_WIDTHS[:change], :right) +
            pad_cell(improvements, COLUMN_WIDTHS[:improvements], :right) +
            pad_cell(regressions, COLUMN_WIDTHS[:regressions], :right)
        end

        # Format a simple score row without comparison columns
        # @param score [ScoreSummary] The score summary
        # @param name_width [Integer] Width for the name column
        # @return [String] Formatted row
        def format_simple_score_row(score, name_width = 20)
          name = "#{colorize("◯", :blue)} #{score.name}"
          value = format_score_value(score.score)
          pad_cell(name, name_width, :left) + " " + pad_cell(value, 10, :right)
        end

        # Format a metric row (3 columns)
        # @param metric [MetricSummary] The metric summary
        # @return [String] Formatted row
        def format_metric_row(metric)
          name = "#{colorize("◯", :magenta)} #{metric.name}"
          value = format_metric_value(metric.metric, metric.unit)
          change = format_change(metric.diff)

          pad_cell(name, COLUMN_WIDTHS[:name], :left) +
            pad_cell(value, COLUMN_WIDTHS[:value], :right) +
            pad_cell(change, COLUMN_WIDTHS[:change], :right)
        end

        # Format a score value as percentage
        # @param score [Float] Score value (0.0 to 1.0)
        # @return [String] Formatted percentage
        def format_score_value(score)
          return colorize("-", :gray) if score.nil?
          colorize("#{(score * 100).round(2)}%", :white)
        end

        # Format a metric value with unit
        # @param value [Float] Metric value
        # @param unit [String] Unit suffix
        # @return [String] Formatted value with unit
        def format_metric_value(value, unit)
          return colorize("-", :gray) if value.nil?

          # Format based on magnitude and type
          formatted = if value == value.to_i
            value.to_i.to_s
          elsif value < 0.01
            value.round(4).to_s
          else
            value.round(2).to_s
          end

          colorize("#{formatted}#{unit}", :white)
        end

        # Format a change value (diff)
        # @param diff [Float, nil] Difference value (as ratio, e.g., 0.05 = +5%)
        # @return [String] Formatted change with color
        def format_change(diff)
          return colorize("-", :gray) if diff.nil?

          # diff is already a ratio, convert to percentage
          percentage = (diff * 100).round(2)
          sign = (percentage >= 0) ? "+" : ""
          formatted = "#{sign}#{percentage}%"

          if percentage > 0
            colorize(formatted, :green)
          elsif percentage < 0
            colorize(formatted, :red)
          else
            colorize(formatted, :gray)
          end
        end

        # Format an improvement/regression count
        # @param count [Integer, nil] Count value
        # @param color [Symbol] Color to apply if non-zero
        # @return [String] Formatted count
        def format_count(count, color = nil)
          return colorize("-", :gray) if count.nil? || count == 0

          if color
            colorize(count.to_s, :dim, color)
          else
            count.to_s
          end
        end

        # Check if any scores have comparison data
        # @param scores [Hash<String, ScoreSummary>] Scores to check
        # @return [Boolean] True if any score has diff data
        def has_comparison_data?(scores)
          scores&.values&.any? { |s| !s.diff.nil? }
        end

        # Format a duration value for display
        # Shows milliseconds for < 1 second, seconds otherwise
        # @param seconds [Float] Duration in seconds
        # @return [String] Formatted duration (e.g., "500ms" or "1.2345s")
        def format_duration(seconds)
          if seconds < 1
            "#{(seconds * 1000).round}ms"
          else
            "#{seconds.round(4)}s"
          end
        end

        # Format an error row for display
        # @param error_message [String] The error message
        # @return [String] Formatted row with red ✗
        def format_error_row(error_message)
          truncated = truncate_error(error_message, MAX_ERROR_LENGTH)
          "#{colorize("✗", :red)} #{truncated}"
        end

        # Truncate error message to max length with ellipsis
        # @param message [String] The error message
        # @param max_length [Integer] Maximum length before truncation
        # @return [String] Truncated message
        def truncate_error(message, max_length)
          return message if message.length <= max_length
          "#{message[0, max_length - 3]}..."
        end

        # Apply ANSI color codes to text
        # @param text [String] Text to colorize
        # @param styles [Array<Symbol>] Color/style names (:gray, :red, :green, etc.)
        # @return [String] Colorized text (or plain text if not a TTY)
        def colorize(text, *styles)
          return text unless $stdout.tty?
          codes = styles.map { |s| COLORS[s] }.compact.join
          "#{codes}#{text}#{COLORS[:reset]}"
        end

        # Pad a cell to a given width, accounting for ANSI codes
        # @param text [String] Cell text (may contain ANSI codes)
        # @param width [Integer] Target width
        # @param align [Symbol] :left or :right alignment
        # @return [String] Padded cell
        def pad_cell(text, width, align)
          visible_length = visible_text_length(text)
          padding = [width - visible_length, 0].max

          case align
          when :right
            " " * padding + text
          else
            text + " " * padding
          end
        end

        # Calculate visible text length, stripping ANSI codes and OSC 8 hyperlinks
        # @param text [String] Text that may contain escape sequences
        # @return [Integer] Visible character count
        def visible_text_length(text)
          text
            .gsub(/\e\[[0-9;]*m/, "")           # ANSI color codes
            .gsub(/\e\]8;;[^\e]*\e\\/, "")      # OSC 8 hyperlink sequences
            .length
        end

        # Create a clickable terminal hyperlink (OSC 8)
        # @param text [String] Display text
        # @param url [String] Target URL
        # @return [String] Hyperlinked text (or plain text with URL if not a TTY)
        def terminal_link(text, url)
          if $stdout.tty?
            "\e]8;;#{url}\e\\#{text}\e]8;;\e\\"
          else
            "#{text}: #{url}"
          end
        end

        # Wrap content lines in a Unicode box with title
        # @param lines [Array<String>] Content lines
        # @param title [String] Box title
        # @return [String] Boxed content
        def wrap_in_box(lines, title)
          # Calculate width from content (strip escape sequences for measurement)
          content_width = lines.map { |l| visible_text_length(l) }.max || 0
          box_width = [content_width + 4, title.length + 6].max
          inner_width = box_width - 2

          result = []

          # Top border with title
          title_str = " #{title} "
          remaining = inner_width - title_str.length - 1
          top = colorize("#{BOX[:top_left]}#{BOX[:horizontal]}", :gray) +
            colorize(title_str, :gray) +
            colorize(BOX[:horizontal] * remaining + BOX[:top_right], :gray)
          result << top

          # Empty line for padding
          result << colorize(BOX[:vertical], :gray) + " " * inner_width + colorize(BOX[:vertical], :gray)

          # Content lines
          lines.each do |line|
            visible_len = visible_text_length(line)
            padding = inner_width - visible_len - 2 # 1 space on each side
            result << colorize(BOX[:vertical], :gray) + " " + line + " " * [padding, 0].max + " " + colorize(BOX[:vertical], :gray)
          end

          # Empty line for padding
          result << colorize(BOX[:vertical], :gray) + " " * inner_width + colorize(BOX[:vertical], :gray)

          # Bottom border
          result << colorize("#{BOX[:bottom_left]}#{BOX[:horizontal] * inner_width}#{BOX[:bottom_right]}", :gray)

          "\n" + result.join("\n")
        end
      end
    end
  end
end
