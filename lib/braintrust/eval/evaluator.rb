# frozen_string_literal: true

module Braintrust
  module Eval
    # Base class for evaluators. Subclass and override #task and #scorers,
    # or instantiate directly with keyword arguments.
    #
    # @example Subclass pattern
    #   class FoodClassifier < Braintrust::Eval::Evaluator
    #     def task
    #       ->(input) { classify(input) }
    #     end
    #
    #     def scorers
    #       [Braintrust::Eval.scorer("exact_match") { |i, e, o| o == e ? 1.0 : 0.0 }]
    #     end
    #   end
    #
    # @example Inline pattern
    #   Braintrust::Eval::Evaluator.new(
    #     task: ->(input) { input.upcase },
    #     scorers: [my_scorer]
    #   )
    class Evaluator
      attr_accessor :task, :scorers, :parameters

      def initialize(task: nil, scorers: [], parameters: {})
        @task = task
        @scorers = scorers
        @parameters = parameters
      end

      # Validate that the evaluator has required fields set.
      # @raise [ArgumentError] if validation fails
      def validate!
        raise ArgumentError, "task is required" unless task
        unless task.respond_to?(:call)
          raise ArgumentError, "task must be callable (respond to :call)"
        end
      end

      # Run this evaluator against the given cases.
      # Delegates to Braintrust::Eval.run with the evaluator's task and scorers.
      #
      # @param cases [Array] The test cases
      # @param on_progress [#call, nil] Optional callback fired after each test case
      # @param quiet [Boolean] If true, suppress result output (default: false)
      # @param project [String, nil] Project name
      # @param experiment [String, nil] Experiment name
      # @param project_id [String, nil] Project UUID (skips project creation)
      # @param dataset [String, Hash, Dataset, DatasetId, nil] Dataset to fetch
      # @param scorers [Array, nil] Additional scorers (merged with evaluator's own)
      # @param parent [Hash, nil] Parent span context
      # @param state [State, nil] Braintrust state
      # @param update [Boolean] If true, allow reusing existing experiment (default: false)
      # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider (defaults to global)
      # @return [Result]
      def run(cases, on_progress: nil, quiet: false,
        project: nil, experiment: nil, project_id: nil,
        dataset: nil, scorers: nil, parent: nil,
        state: nil, update: false, tracer_provider: nil)
        all_scorers = scorers ? self.scorers + scorers : self.scorers
        Braintrust::Eval.run(
          task: task, scorers: all_scorers, cases: cases, dataset: dataset,
          project: project, experiment: experiment, project_id: project_id,
          parent: parent, on_progress: on_progress, quiet: quiet,
          state: state, update: update, tracer_provider: tracer_provider
        )
      end
    end
  end
end
