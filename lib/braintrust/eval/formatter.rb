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

      class << self
        # Format an experiment summary for CLI output
        # @param summary [ExperimentSummary] The experiment summary
        # @return [String] Formatted output with box drawing and colors
        def format_experiment_summary(summary)
          return "" unless summary

          lines = []

          # Metadata section
          lines << format_metadata_row("Project", summary.project_name)
          lines << format_metadata_row("Experiment", summary.experiment_name)
          lines << format_metadata_row("ID", summary.experiment_id)
          lines << format_metadata_row("Duration", format_duration(summary.duration))
          lines << format_metadata_row("Errors", summary.error_count.to_s)

          # Scores section (if any)
          if summary.scores&.any?
            lines << ""
            lines << colorize("Scores", :white)

            # Calculate max scorer name length for alignment
            max_name_len = summary.scores.values.map { |s| s.name.length }.max || 0
            name_width = [max_name_len + 2, 20].max # +2 for "◯ " prefix

            summary.scores.each_value do |score|
              lines << format_score_row(score, name_width)
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

        # Format a metadata row (label: value)
        # @param label [String] Row label
        # @param value [String] Row value
        # @return [String] Formatted row
        def format_metadata_row(label, value)
          "#{colorize(label + ":", :dim)} #{value}"
        end

        # Format duration for display
        # @param duration [Float] Duration in seconds
        # @return [String] Formatted duration (e.g., "1.2345s" or "123ms")
        def format_duration(duration)
          if duration < 1
            "#{(duration * 1000).round(0)}ms"
          else
            "#{duration.round(4)}s"
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

        # Format a score row for display
        # @param score [ScorerStats] The scorer statistics
        # @param name_width [Integer] Width for the name column
        # @return [String] Formatted row
        def format_score_row(score, name_width = 20)
          name = "#{colorize("◯", :blue)} #{score.name}"
          value = colorize("#{(score.score_mean * 100).round(2)}%", :white)
          pad_cell(name, name_width, :left) + " " + pad_cell(value, 10, :right)
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
          # Strip ANSI color codes: \e[...m
          # Strip OSC 8 hyperlinks: \e]8;;...\e\\ (the URL part is invisible)
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
