# frozen_string_literal: true

require_relative "formatter"
require_relative "summary"

module Braintrust
  module Eval
    # Result represents the outcome of an evaluation run
    # Contains experiment metadata, errors, timing information, and raw score data
    class Result
      attr_reader :experiment_id, :experiment_name, :project_id, :project_name,
        :permalink, :errors, :duration, :scores

      # Create a new result
      # @param experiment_id [String] The experiment ID
      # @param experiment_name [String] The experiment name
      # @param project_id [String] The project ID
      # @param project_name [String] The project name
      # @param permalink [String] Link to view the experiment in Braintrust UI
      # @param errors [Array<String>] List of errors that occurred
      # @param duration [Float] Duration in seconds
      # @param scores [Hash, nil] Raw score data { scorer_name => Array<Numeric> }
      def initialize(experiment_id:, experiment_name:, project_id:, project_name:,
        permalink:, errors:, duration:, scores: nil)
        @experiment_id = experiment_id
        @experiment_name = experiment_name
        @project_id = project_id
        @project_name = project_name
        @permalink = permalink
        @errors = errors
        @duration = duration
        @scores = scores
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

      # Get the experiment summary (lazily computed)
      # @return [ExperimentSummary] Summary view model for Formatter
      def summary
        @summary ||= build_summary
      end

      # Format the result as a human-readable string (Go SDK format)
      # @return [String]
      def to_s
        [
          "Experiment: #{experiment_name}",
          "Project: #{project_name}",
          "ID: #{experiment_id}",
          "Link: #{permalink}",
          "Duration: #{duration.round(4)}s",
          "Errors: #{errors.length}"
        ].join("\n")
      end

      # Format the result as a pretty CLI output with box drawing and colors
      # @return [String]
      def to_pretty
        Formatter.format_experiment_summary(summary)
      end

      # Get statistics for all scorers (lazily computed from scores)
      # @return [Hash<String, ScorerStats>] Scorer stats keyed by scorer name
      def scorer_stats
        @scorer_stats ||= build_scorer_stats
      end

      private

      # Build scorer statistics from raw score data
      # @return [Hash<String, ScorerStats>] Scorer stats keyed by scorer name
      def build_scorer_stats
        return {} if scores.nil? || scores.empty?

        stats = {}
        scores.each do |name, score_values|
          next if score_values.empty?
          mean = score_values.sum.to_f / score_values.size
          stats[name] = ScorerStats.new(name: name, score_mean: mean)
        end
        stats
      end

      # Build experiment summary view model
      # @return [ExperimentSummary] Summary with all data for Formatter
      def build_summary
        ExperimentSummary.new(
          project_name: project_name,
          experiment_name: experiment_name,
          experiment_id: experiment_id,
          experiment_url: permalink,
          scores: scorer_stats,
          duration: duration,
          error_count: errors.length,
          errors: errors
        )
      end
    end
  end
end
