# frozen_string_literal: true

module Braintrust
  module Eval
    # Result represents the outcome of an evaluation run
    # Contains experiment metadata, errors, and timing information
    class Result
      attr_reader :experiment_id, :experiment_name, :project_id,
        :permalink, :errors, :duration

      # Create a new result
      # @param experiment_id [String] The experiment ID
      # @param experiment_name [String] The experiment name
      # @param project_id [String] The project ID
      # @param permalink [String] Link to view the experiment in Braintrust UI
      # @param errors [Array<String>] List of errors that occurred
      # @param duration [Float] Duration in seconds
      def initialize(experiment_id:, experiment_name:, project_id:,
        permalink:, errors:, duration:)
        @experiment_id = experiment_id
        @experiment_name = experiment_name
        @project_id = project_id
        @permalink = permalink
        @errors = errors
        @duration = duration
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
        [
          "Experiment: #{experiment_name}",
          "ID: #{experiment_id}",
          "Link: #{permalink}",
          "Duration: #{duration.round(2)}s",
          "Errors: #{errors.length}"
        ].join("\n")
      end
    end
  end
end
