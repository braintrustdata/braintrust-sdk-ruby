# frozen_string_literal: true

module Braintrust
  module Eval
    # Aggregated statistics for a single scorer across test cases
    # @attr name [String] Scorer name
    # @attr score_mean [Float] Mean score (0.0 to 1.0)
    ScorerStats = Struct.new(:name, :score_mean, keyword_init: true)

    # Summary of results from an Experiment
    # Typically used to generate experiment output
    # @attr project_name [String] Project name
    # @attr experiment_name [String] Experiment name
    # @attr experiment_id [String] Experiment ID
    # @attr experiment_url [String] URL to view experiment in Braintrust UI
    # @attr scores [Hash<String, ScorerStats>] Scorer stats keyed by scorer name
    # @attr duration [Float] Duration in seconds
    # @attr error_count [Integer] Number of errors
    # @attr errors [Array<String>] Error messages with locations
    ExperimentSummary = Struct.new(
      :project_name,
      :experiment_name,
      :experiment_id,
      :experiment_url,
      :scores,
      :duration,
      :error_count,
      :errors,
      keyword_init: true
    )
  end
end
