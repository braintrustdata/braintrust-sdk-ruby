# frozen_string_literal: true

module Braintrust
  module Eval
    # Scoped context for a single evaluation run.
    # Owns lifecycle of eval-specific resources.
    # Created at eval start, disposed at eval end.
    class Context
      attr_reader :experiment_id

      # @param experiment_id [String] The experiment ID
      def initialize(experiment_id:)
        @experiment_id = experiment_id
      end

      # Dispose of resources (for eager cleanup)
      def dispose
        # Currently no resources to dispose
        # This method is kept for future extensibility
      end
    end
  end
end
