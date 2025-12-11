# frozen_string_literal: true

require_relative "formatter"
require_relative "summary"

module Braintrust
  module Eval
    # Result represents the outcome of an evaluation run
    # Contains experiment metadata, errors, timing information, and summary data
    class Result
      attr_reader :experiment_id, :experiment_name, :project_id, :project_name,
        :permalink, :errors, :duration, :scores, :summary

      # Create a new result
      # @param experiment_id [String, nil] The experiment ID (nil for local-only mode)
      # @param experiment_name [String] The experiment name
      # @param project_id [String, nil] The project ID (nil for local-only mode)
      # @param project_name [String] The project name
      # @param permalink [String, nil] Link to view the experiment in Braintrust UI
      # @param errors [Array<String>] List of errors that occurred
      # @param duration [Float] Duration in seconds
      # @param scores [Hash, nil] Raw score data { scorer_name => Array<Numeric> }
      # @param summary [ExperimentSummary, nil] Pre-computed summary (if nil, computed lazily)
      def initialize(experiment_id:, experiment_name:, project_id:, project_name:,
        permalink:, errors:, duration:, scores: nil, summary: nil)
        @experiment_id = experiment_id
        @experiment_name = experiment_name
        @project_id = project_id
        @project_name = project_name
        @permalink = permalink
        @errors = errors
        @duration = duration
        @scores = scores
        @summary = summary || build_summary_without_comparison
      end

      # Check if the evaluation was successful (no errors)
      # @return [Boolean]
      def success?
        errors.empty?
      end

      # Check if the evaluation failed (has errors)
      # @return [Boolean]
      def failed?
        !success?
      end

      # Format the result as a human-readable string (Go SDK format)
      # @return [String]
      def to_s
        lines = [
          "Experiment: #{experiment_name}",
          "Project: #{project_name}"
        ]
        lines << "ID: #{experiment_id}" if experiment_id
        lines << "Link: #{permalink}" if permalink
        lines << "Duration: #{duration.round(4)}s"
        lines << "Errors: #{errors.length}"
        lines.join("\n")
      end

      # Format the result as a pretty CLI output with box drawing and colors
      # @return [String]
      def to_pretty
        Formatter.format_experiment_summary(summary)
      end

      private

      # Build summary from raw scores when comparison data is unavailable
      # @return [ExperimentSummary]
      def build_summary_without_comparison
        ExperimentSummary.from_raw_scores(
          scores || {},
          {
            project_name: project_name,
            experiment_name: experiment_name,
            experiment_id: experiment_id,
            experiment_url: permalink,
            duration: duration,
            error_count: errors.length,
            errors: errors
          }
        )
      end
    end
  end
end
