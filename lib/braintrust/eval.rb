# frozen_string_literal: true

require_relative "scorer"
require_relative "task"
require_relative "functions"
require_relative "eval/context"
require_relative "eval/evaluator"
require_relative "eval/functions"
require_relative "eval/runner"
require_relative "eval/scorer"
require_relative "api/internal/projects"
require_relative "api/internal/experiments"
require_relative "dataset"

require "opentelemetry/sdk"
require "json"

module Braintrust
  # Evaluation framework for testing AI systems with custom test cases and scoring functions.
  #
  # The Eval module provides tools for running systematic evaluations of your AI systems. An
  # evaluation consists of:
  # - **Cases**: Test inputs with optional expected outputs
  # - **Task**: The code/model being evaluated (a {Braintrust::Task} or callable)
  # - **Scorers**: Functions that judge the quality of outputs (String name, {Braintrust::Scorer}, or callable)
  #
  # Tasks and scorers use keyword arguments. Only declare the keywords you need —
  # extra kwargs are automatically filtered out.
  #
  # When using multiple scorers, each must have a unique name — scores are keyed
  # by name, so duplicates overwrite each other. Use +Scorer.new("name")+ or a
  # Scorer subclass to assign names. Anonymous lambdas default to "scorer".
  #
  # @example Basic evaluation with inline cases
  #   require "braintrust"
  #
  #   Braintrust.init
  #
  #   Braintrust::Eval.run(
  #     project: "my-project",
  #     experiment: "food-classifier",
  #     cases: [
  #       {input: "apple", expected: "fruit"},
  #       {input: "carrot", expected: "vegetable"},
  #       {input: "banana", expected: "fruit"}
  #     ],
  #     task: ->(input:) { input.include?("a") ? "fruit" : "vegetable" },
  #     scorers: [
  #       ->(expected:, output:) { output == expected ? 1.0 : 0.0 }
  #     ]
  #   )
  #
  # @example Different ways to define scorers
  #   # String — references a scorer defined in your Braintrust project
  #   scorers: ["accuracy-scorer", "relevance-scorer"]
  #
  #   # Lambda — declare only the kwargs you need (input:, expected:, output:, metadata:, tags:)
  #   exact = ->(expected:, output:) { output == expected ? 1.0 : 0.0 }
  #
  #   # Named scorer with Scorer.new
  #   named = Braintrust::Scorer.new("case_insensitive") { |expected:, output:| output.downcase == expected.downcase ? 1.0 : 0.0 }
  #
  #   # Class-based pattern (auto-derives name from class: "fuzzy_match")
  #   class FuzzyMatch
  #     include Braintrust::Scorer
  #     def call(expected:, output:)
  #       # scoring logic here
  #       1.0
  #     end
  #   end
  #
  # @example Different ways to define tasks
  #   # Lambda with keyword args
  #   task = ->(input:) { process(input) }
  #
  #   # Named task with Task.new
  #   task = Braintrust::Task.new("my_task") { |input:| process(input) }
  #
  #   # Class-based pattern
  #   class MyTask
  #     include Braintrust::Task
  #     def call(input:)
  #       process(input)
  #     end
  #   end
  #
  #   # Legacy lambdas (positional args) are also accepted for backwards compatibility
  #   legacy_task = ->(input) { process(input) }
  #
  # @example Using datasets instead of inline cases
  #   Braintrust::Eval.run(
  #     project: "my-project",
  #     experiment: "with-dataset",
  #     dataset: "my-dataset-name", # fetches from same project
  #     task: ->(input:) { input.upcase },
  #     scorers: [->(expected:, output:) { output == expected ? 1.0 : 0.0 }]
  #   )
  #
  #   # Or with more options
  #   Braintrust::Eval.run(
  #     project: "my-project",
  #     experiment: "with-dataset-options",
  #     dataset: { name: "my-dataset", project: "other-project", version: "1.0", limit: 100 },
  #     task: ->(input:) { input.upcase },
  #     scorers: [->(expected:, output:) { output == expected ? 1.0 : 0.0 }]
  #   )
  #
  # @example Using parameters for configurable tasks
  #   # Tasks and scorers that declare `parameters:` receive it automatically.
  #   # Those that don't are unaffected — KeywordFilter strips unknown kwargs.
  #   Braintrust::Eval.run(
  #     project: "my-project",
  #     experiment: "with-params",
  #     cases: [{input: "hello", expected: "HELLO!"}],
  #     task: ->(input:, parameters:) {
  #       suffix = parameters["suffix"] || ""
  #       input.upcase + suffix
  #     },
  #     scorers: [->(expected:, output:) { output == expected ? 1.0 : 0.0 }],
  #     parameters: {"suffix" => "!"}
  #   )
  #
  # @example Using metadata and tags
  #   Braintrust::Eval.run(
  #     project: "my-project",
  #     experiment: "with-metadata",
  #     cases: [
  #       {
  #         input: "apple",
  #         expected: "fruit",
  #         tags: ["tropical", "sweet"],
  #         metadata: {threshold: 0.9, category: "produce"}
  #       }
  #     ],
  #     task: ->(input:) { "fruit" },
  #     scorers: [
  #       ->(expected:, output:, metadata:) {
  #         threshold = metadata[:threshold] || 0.5
  #         # scoring logic using threshold
  #         1.0
  #       }
  #     ],
  #     tags: ["v1", "production"],
  #     metadata: { model: "gpt-4", temperature: 0.7, version: "1.0.0" }
  #   )
  module Eval
    class << self
      # @deprecated Use {Braintrust::Scorer.new} instead
      def scorer(name, callable = nil, &block)
        Log.warn_once(:eval_scorer, "Braintrust::Eval.scorer is deprecated: use Braintrust::Scorer.new instead.")
        block = callable.method(:call) if callable && !block
        Scorer.new(name, &block)
      end

      # Run an evaluation
      # @param project [String, nil] The project name (triggers full API mode: creates project + experiment)
      # @param experiment [String, nil] The experiment name
      # @param cases [Array, Enumerable, nil] The test cases (mutually exclusive with dataset)
      # @param dataset [String, Hash, nil] Dataset to fetch (mutually exclusive with cases)
      #   - String: dataset name (fetches from same project)
      #   - Hash: {name:, id:, project:, version:, limit:}
      # @param task [#call] The task to evaluate (must be callable)
      # @param scorers [Array<String, Scorer, #call>] The scorers to use (String names, Scorer objects, or callables)
      # @param on_progress [#call, nil] Optional callback fired after each test case.
      #   Receives a Hash: {"data" => output, "scores" => {name => value}} on success,
      #   or {"error" => message} on failure.
      # @param parallelism [Integer] Number of parallel workers (default: 1).
      #   When parallelism > 1, test cases are executed concurrently using a thread pool.
      #   The task and scorers MUST be thread-safe when using parallelism > 1.
      # @param tags [Array<String>] Optional experiment tags
      # @param metadata [Hash] Optional experiment metadata
      # @param update [Boolean] If true, allow reusing existing experiment (default: false)
      # @param quiet [Boolean] If true, suppress result output (default: false)
      # @param state [State, nil] Braintrust state (defaults to global state)
      # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider (defaults to global)
      # @param project_id [String, nil] Project UUID (skips project creation when provided)
      # @param parent [Hash, nil] Parent span context ({object_type:, object_id:, generation:})
      # @param parameters [Hash, nil] Runtime parameters passed to task and scorers as a `parameters:` keyword argument
      # @return [Result]
      def run(task:, scorers:, project: nil, experiment: nil,
        cases: nil, dataset: nil, on_progress: nil,
        parallelism: 1, tags: nil, metadata: nil, update: false, quiet: false,
        state: nil, tracer_provider: nil, project_id: nil, parent: nil,
        parameters: nil)
        # Validate required parameters
        validate_params!(task: task, scorers: scorers, cases: cases, dataset: dataset)

        experiment_id = nil
        project_name = project

        # Full API mode: project name or project_id provided, resolve via API
        if project || project_id
          state ||= Braintrust.current_state
          state.login

          if dataset
            resolved = resolve_dataset(dataset, project, state)
            cases = resolved[:cases]
          end

          # Skip experiment creation for remote evals (parent present).
          # The OTLP backend creates experiments from ingested spans.
          unless parent
            project_id, project_name = resolve_project(state, project, project_id)
            experiment_id = create_experiment(
              state, experiment, project_id,
              update: update, tags: tags, metadata: metadata,
              dataset_id: resolved&.dig(:dataset_id),
              dataset_version: resolved&.dig(:dataset_version)
            )
            parent = {object_type: "experiment_id", object_id: experiment_id}
          end
        end

        # Build normalized context and run
        context = Context.build(
          task: task,
          scorers: scorers,
          cases: cases,
          experiment_id: experiment_id,
          experiment_name: experiment,
          project_id: project_id,
          project_name: project_name,
          state: state,
          tracer_provider: tracer_provider,
          on_progress: on_progress,
          parent: parent,
          parameters: parameters
        )
        result = Runner.new(context).run(parallelism: parallelism)

        # Print result summary unless quiet
        print_result(result) unless quiet

        result
      end

      private

      # Print result summary to stdout
      # @param result [Result] The evaluation result
      def print_result(result)
        puts result.to_pretty
      end

      # Validate required parameters
      # @raise [ArgumentError] if validation fails
      def validate_params!(task:, scorers:, cases:, dataset:)
        raise ArgumentError, "task is required" unless task
        raise ArgumentError, "scorers is required" unless scorers

        # Validate cases and dataset are mutually exclusive
        if cases && dataset
          raise ArgumentError, "cannot specify both 'cases' and 'dataset' - they are mutually exclusive"
        end

        # Validate at least one data source is provided
        unless cases || dataset
          raise ArgumentError, "must specify either 'cases' or 'dataset'"
        end

        # Validate task is callable
        unless task.respond_to?(:call)
          raise ArgumentError, "task must be callable (respond to :call)"
        end
      end

      # Resolve project by name or ID. Creates if needed.
      # @return [Array(String, String)] [project_id, project_name]
      def resolve_project(state, project, project_id)
        if project_id
          [project_id, project]
        else
          result = API::Internal::Projects.new(state).create(name: project)
          [result["id"], result["name"]]
        end
      end

      # Create an experiment in the given project.
      # @return [String] experiment_id
      def create_experiment(state, name, project_id,
        update: false, tags: nil, metadata: nil,
        dataset_id: nil, dataset_version: nil)
        result = API::Internal::Experiments.new(state).create(
          name: name,
          project_id: project_id,
          ensure_new: !update,
          tags: tags,
          metadata: metadata,
          dataset_id: dataset_id,
          dataset_version: dataset_version
        )
        result["id"]
      end

      # Resolve dataset parameter to cases with metadata for experiment linking
      # @param dataset [String, Hash, Dataset] Dataset specifier or instance
      # @param project [String] Project name (used as default if not specified)
      # @param state [State] Braintrust state
      # @return [Hash] Hash with :cases, :dataset_id, and :dataset_version
      def resolve_dataset(dataset, project, state)
        limit = nil

        dataset_obj = case dataset
        when Dataset
          dataset
        when Dataset::ID
          Dataset.new(id: dataset.id, state: state)
        when String
          Dataset.new(name: dataset, project: project, state: state)
        when Hash
          opts = dataset.dup
          limit = opts.delete(:limit)
          opts[:project] ||= project
          opts[:state] = state
          Dataset.new(**opts)
        else
          raise ArgumentError, "dataset must be String, Hash, Dataset, or Dataset::ID, got #{dataset.class}"
        end

        cases = dataset_obj.fetch_all(limit: limit)

        # Use pinned version if available, otherwise compute from max(_xact_id)
        version = dataset_obj.version
        version ||= cases
          .filter_map { |c| c[:origin] && JSON.parse(c[:origin])["_xact_id"] }
          .max

        {cases: cases, dataset_id: dataset_obj.id, dataset_version: version}
      end
    end
  end
end
