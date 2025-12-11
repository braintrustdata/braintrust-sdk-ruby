# frozen_string_literal: true

module Braintrust
  module Eval
    # Score summary - unified for both local and comparison modes
    # For local mode: diff/improvements/regressions are nil
    # @attr name [String] Score name
    # @attr score [Float] Average score (0.0 to 1.0)
    # @attr diff [Float, nil] Difference vs baseline (percentage, e.g., 0.05 = +5%)
    # @attr improvements [Integer, nil] Count of improved test cases
    # @attr regressions [Integer, nil] Count of regressed test cases
    class ScoreSummary
      attr_reader :name, :score, :diff, :improvements, :regressions

      def initialize(name:, score:, diff: nil, improvements: nil, regressions: nil)
        @name = name
        @score = score
        @diff = diff
        @improvements = improvements
        @regressions = regressions
      end

      # Build from raw score values (computes mean)
      # @param name [String] Score name
      # @param values [Array<Numeric>] Raw score values
      # @return [ScoreSummary]
      def self.from_values(name, values)
        return new(name: name, score: 0.0) if values.empty?
        mean = values.sum.to_f / values.size
        new(name: name, score: mean)
      end
    end

    # Metric summary for server-computed metrics (duration, tokens, etc.)
    # @attr name [String] Metric name
    # @attr metric [Float] Metric value
    # @attr unit [String] Unit label (e.g., "ms", "$", "tok")
    # @attr diff [Float, nil] Difference vs baseline (percentage)
    MetricSummary = Struct.new(:name, :metric, :unit, :diff, keyword_init: true)

    # Comparison metadata for the summary header
    # @attr baseline_experiment_id [String, nil] Baseline experiment ID
    # @attr baseline_experiment_name [String, nil] Baseline experiment name
    ComparisonInfo = Struct.new(:baseline_experiment_id, :baseline_experiment_name, keyword_init: true)

    # Summary of results from an Experiment
    # Typically used to generate experiment output
    # @attr project_name [String] Project name
    # @attr experiment_name [String] Experiment name
    # @attr experiment_id [String, nil] Experiment ID (nil for local-only mode)
    # @attr experiment_url [String, nil] URL to view experiment in Braintrust UI
    # @attr scores [Hash<String, ScoreSummary>] Score summaries keyed by scorer name
    # @attr metrics [Hash<String, MetricSummary>, nil] Metric summaries (nil for local mode)
    # @attr comparison [ComparisonInfo, nil] Comparison metadata (nil for local mode)
    # @attr duration [Float] Duration in seconds
    # @attr error_count [Integer] Number of errors
    # @attr errors [Array<String>] Error messages with locations
    class ExperimentSummary
      attr_reader :project_name, :experiment_name, :experiment_id, :experiment_url,
        :scores, :metrics, :comparison, :duration, :error_count, :errors

      def initialize(project_name:, experiment_name:, experiment_id:, experiment_url:,
        scores:, duration:, error_count:, errors:, metrics: nil, comparison: nil)
        @project_name = project_name
        @experiment_name = experiment_name
        @experiment_id = experiment_id
        @experiment_url = experiment_url
        @scores = scores
        @metrics = metrics
        @comparison = comparison
        @duration = duration
        @error_count = error_count
        @errors = errors
      end

      # Build from raw score values (local mode, no comparison)
      # @param raw_scores [Hash<String, Array<Numeric>>] Raw score values
      # @param metadata [Hash] Experiment metadata (project_name, experiment_name, duration, errors, etc.)
      # @return [ExperimentSummary]
      def self.from_raw_scores(raw_scores, metadata)
        scores = (raw_scores || {}).map do |name, values|
          [name.to_s, ScoreSummary.from_values(name.to_s, values)]
        end.to_h
        new(
          scores: scores,
          metrics: nil,
          comparison: nil,
          **metadata
        )
      end
    end
  end
end
