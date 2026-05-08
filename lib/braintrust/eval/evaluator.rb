# frozen_string_literal: true

module Braintrust
  module Eval
    # Base class for evaluators. Subclass and override #task and #scorers,
    # or instantiate directly with keyword arguments.
    #
    # Evaluators are used with the dev server, which reports scorer names
    # to the Braintrust UI. Always use named scorers (via Scorer.new or
    # subclass) so they display meaningfully.
    #
    # @example Subclass pattern
    #   class FoodClassifier < Braintrust::Eval::Evaluator
    #     def task
    #       ->(input:) { classify(input) }
    #     end
    #
    #     def scorers
    #       [Braintrust::Scorer.new("exact_match") { |expected:, output:| output == expected ? 1.0 : 0.0 }]
    #     end
    #   end
    #
    # @example Inline pattern
    #   Braintrust::Eval::Evaluator.new(
    #     task: ->(input:) { input.upcase },
    #     scorers: [
    #       Braintrust::Scorer.new("exact_match") { |expected:, output:| output == expected ? 1.0 : 0.0 }
    #     ]
    #   )
    #
    # @example Remote eval with parameters (for Playground UI)
    #   Braintrust::Eval::Evaluator.new(
    #     task: ->(input:, parameters:) {
    #       model = parameters["model"] || "gpt-4"
    #       # Use model to generate response...
    #     },
    #     scorers: [Braintrust::Scorer.new("exact") { |expected:, output:| output == expected ? 1.0 : 0.0 }],
    #     parameters: {
    #       "model" => {type: "string", default: "gpt-4", description: "Model to use"}
    #     }
    #   )
    class Evaluator
      attr_accessor :task, :scorers, :classifiers, :parameters

      def initialize(task: nil, scorers: [], classifiers: [], parameters: {})
        @task = task
        @scorers = scorers
        @classifiers = classifiers
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
      # @param dataset [String, Hash, Dataset, Dataset::ID, nil] Dataset to fetch
      # @param scorers [Array, nil] Additional scorers (merged with evaluator's own)
      # @param classifiers [Array, nil] Additional classifiers (merged with evaluator's own)
      # @param parent [Hash, nil] Parent span context
      # @param state [State, nil] Braintrust state
      # @param update [Boolean] If true, allow reusing existing experiment (default: false)
      # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider (defaults to global)
      # @return [Result]
      def run(cases, on_progress: nil, quiet: false,
        project: nil, experiment: nil, project_id: nil,
        dataset: nil, scorers: nil, classifiers: nil, parent: nil,
        state: nil, update: false, tracer_provider: nil,
        parameters: nil)
        all_scorers = scorers ? self.scorers + scorers : self.scorers
        all_classifiers = classifiers ?
          self.classifiers + classifiers :
          self.classifiers
        Braintrust::Eval.run(
          task: task, scorers: all_scorers, classifiers: all_classifiers,
          cases: cases, dataset: dataset, project: project,
          experiment: experiment, project_id: project_id, parent: parent,
          on_progress: on_progress, quiet: quiet, state: state, update: update,
          tracer_provider: tracer_provider, parameters: parameters
        )
      end
    end
  end
end
