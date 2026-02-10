# frozen_string_literal: true

require_relative "eval/scorer"
require_relative "eval/runner"
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
  # - **Task**: The code/model being evaluated
  # - **Scorers**: Functions that judge the quality of outputs
  #
  # @example Basic evaluation with inline cases
  #   require "braintrust"
  #
  #   Braintrust.init
  #
  #   # Define a simple task (the code being evaluated)
  #   task = ->(input) { input.include?("a") ? "fruit" : "vegetable" }
  #
  #   # Run evaluation with inline cases
  #   Braintrust::Eval.run(
  #     project: "my-project",
  #     experiment: "food-classifier",
  #     cases: [
  #       {input: "apple", expected: "fruit"},
  #       {input: "carrot", expected: "vegetable"},
  #       {input: "banana", expected: "fruit"}
  #     ],
  #     task: task,
  #     scorers: [
  #       # Named scorer with Eval.scorer
  #       Braintrust::Eval.scorer("exact_match") do |input, expected, output|
  #         output == expected ? 1.0 : 0.0
  #       end
  #     ]
  #   )
  #
  # @example Different ways to define scorers (recommended patterns)
  #   # Method reference (auto-uses method name as scorer name)
  #   def exact_match(input, expected, output)
  #     output == expected ? 1.0 : 0.0
  #   end
  #
  #   # Named scorer with Eval.scorer
  #   case_insensitive = Braintrust::Eval.scorer("case_insensitive") do |input, expected, output|
  #     output.downcase == expected.downcase ? 1.0 : 0.0
  #   end
  #
  #   # Callable class with name method
  #   class FuzzyMatch
  #     def name
  #       "fuzzy_match"
  #     end
  #
  #     def call(input, expected, output, metadata = {})
  #       threshold = metadata[:threshold] || 0.8
  #       # scoring logic here
  #       1.0
  #     end
  #   end
  #
  #   # Anonymous lambda that returns named score object
  #   multi_score = ->(input, expected, output) {
  #     [
  #       {name: "exact_match", score: output == expected ? 1.0 : 0.0},
  #       {name: "length_match", score: output.length == expected.length ? 1.0 : 0.0}
  #     ]
  #   }
  #
  #   # All can be used together
  #   Braintrust::Eval.run(
  #     project: "my-project",
  #     experiment: "scorer-examples",
  #     cases: [{input: "test", expected: "test"}],
  #     task: ->(input) { input },
  #     scorers: [method(:exact_match), case_insensitive, FuzzyMatch.new, multi_score]
  #   )
  #
  # @example Different ways to define tasks
  #   # Lambda
  #   task_lambda = ->(input) { "result" }
  #
  #   # Proc
  #   task_proc = proc { |input| "result" }
  #
  #   # Method reference
  #   def my_task(input)
  #     "result"
  #   end
  #   task_method = method(:my_task)
  #
  #   # Callable class
  #   class MyTask
  #     def call(input)
  #       "result"
  #     end
  #   end
  #   task_class = MyTask.new
  #
  #   # All of these can be used as the task parameter
  #   Braintrust::Eval.run(
  #     project: "my-project",
  #     experiment: "task-examples",
  #     cases: [{input: "test"}],
  #     task: task_lambda, # or task_proc, task_method, task_class
  #     scorers: [
  #       Braintrust::Eval.scorer("my_scorer") { |input, expected, output| 1.0 }
  #     ]
  #   )
  #
  # @example Using datasets instead of inline cases
  #   # Fetch cases from a dataset stored in Braintrust
  #   Braintrust::Eval.run(
  #     project: "my-project",
  #     experiment: "with-dataset",
  #     dataset: "my-dataset-name", # fetches from same project
  #     task: ->(input) { "result" },
  #     scorers: [
  #       Braintrust::Eval.scorer("my_scorer") { |input, expected, output| 1.0 }
  #     ]
  #   )
  #
  #   # Or with more options
  #   Braintrust::Eval.run(
  #     project: "my-project",
  #     experiment: "with-dataset-options",
  #     dataset: {
  #       name: "my-dataset",
  #       project: "other-project",
  #       version: "1.0",
  #       limit: 100
  #     },
  #     task: ->(input) { "result" },
  #     scorers: [
  #       Braintrust::Eval.scorer("my_scorer") { |input, expected, output| 1.0 }
  #     ]
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
  #     task: ->(input) { "fruit" },
  #     scorers: [
  #       # Scorer can access case metadata
  #       Braintrust::Eval.scorer("threshold_match") do |input, expected, output, metadata|
  #         threshold = metadata[:threshold] || 0.5
  #         # scoring logic using threshold
  #         1.0
  #       end
  #     ],
  #     # Experiment-level tags and metadata
  #     tags: ["v1", "production"],
  #     metadata: {
  #       model: "gpt-4",
  #       temperature: 0.7,
  #       version: "1.0.0"
  #     }
  #   )
  module Eval
    class << self
      # Create a scorer with a name and callable
      # @param name [String] The scorer name
      # @param callable [#call, nil] Optional callable (if not using block)
      # @param block [Proc] The scorer block
      # @return [Scorer]
      def scorer(name, callable = nil, &block)
        Scorer.new(name, callable, &block)
      end

      # Run an evaluation
      # @param project [String] The project name
      # @param experiment [String] The experiment name
      # @param cases [Array, Enumerable, nil] The test cases (mutually exclusive with dataset)
      # @param dataset [String, Hash, nil] Dataset to fetch (mutually exclusive with cases)
      #   - String: dataset name (fetches from same project)
      #   - Hash: {name:, id:, project:, version:, limit:}
      # @param task [#call] The task to evaluate (must be callable)
      # @param scorers [Array<Scorer, #call>] The scorers to use (Scorer objects or callables)
      # @param parallelism [Integer] Number of parallel workers (default: 1).
      #   When parallelism > 1, test cases are executed concurrently using a thread pool.
      #   The task and scorers MUST be thread-safe when using parallelism > 1.
      # @param tags [Array<String>] Optional experiment tags
      # @param metadata [Hash] Optional experiment metadata
      # @param update [Boolean] If true, allow reusing existing experiment (default: false)
      # @param quiet [Boolean] If true, suppress result output (default: false)
      # @param api [API, nil] Braintrust API client (defaults to API.new using global state)
      # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider (defaults to global)
      # @return [Result]
      def run(project:, experiment:, task:, scorers:,
        cases: nil, dataset: nil,
        parallelism: 1, tags: nil, metadata: nil, update: false, quiet: false,
        api: nil, tracer_provider: nil)
        # Validate required parameters
        validate_params!(project: project, experiment: experiment,
          cases: cases, dataset: dataset, task: task, scorers: scorers)

        # Get API from parameter or create from global state
        api ||= API.new

        # Ensure logged in (to populate org_name, etc.)
        # login is idempotent and returns early if already logged in
        api.login

        # Resolve dataset to cases if dataset parameter provided
        dataset_id = nil
        dataset_version = nil

        if dataset
          resolved = resolve_dataset(dataset, project, api)
          cases = resolved[:cases]
          dataset_id = resolved[:dataset_id]
          dataset_version = resolved[:dataset_version]
        end

        # Register project and experiment via internal API
        projects_api = API::Internal::Projects.new(api.state)
        experiments_api = API::Internal::Experiments.new(api.state)

        project_result = projects_api.create(name: project)
        experiment_result = experiments_api.create(
          name: experiment,
          project_id: project_result["id"],
          ensure_new: !update,
          tags: tags,
          metadata: metadata,
          dataset_id: dataset_id,
          dataset_version: dataset_version
        )

        experiment_id = experiment_result["id"]
        project_id = project_result["id"]
        project_name = project_result["name"]

        # Enable span cache for evaluation
        api.state.span_cache.start

        begin
          # Instantiate Runner and run evaluation
          runner = Runner.new(
            experiment_id: experiment_id,
            experiment_name: experiment,
            project_id: project_id,
            project_name: project_name,
            task: task,
            scorers: scorers,
            api: api,
            tracer_provider: tracer_provider
          )
          result = runner.run(cases, parallelism: parallelism)

          # Print result summary unless quiet
          print_result(result) unless quiet

          result
        ensure
          # Disable and clear span cache after evaluation
          api.state.span_cache.stop
        end
      end

      private

      # Print result summary to stdout
      # @param result [Result] The evaluation result
      def print_result(result)
        puts result.to_pretty
      end

      # Validate required parameters
      # @raise [ArgumentError] if validation fails
      def validate_params!(project:, experiment:, cases:, dataset:, task:, scorers:)
        raise ArgumentError, "project is required" unless project
        raise ArgumentError, "experiment is required" unless experiment
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

      # Resolve dataset parameter to cases with metadata for experiment linking
      # @param dataset [String, Hash, Dataset] Dataset specifier or instance
      # @param project [String] Project name (used as default if not specified)
      # @param api [API] Braintrust API client
      # @return [Hash] Hash with :cases, :dataset_id, and :dataset_version
      def resolve_dataset(dataset, project, api)
        limit = nil

        dataset_obj = case dataset
        when Dataset
          dataset
        when String
          Dataset.new(name: dataset, project: project, api: api)
        when Hash
          opts = dataset.dup
          limit = opts.delete(:limit)
          opts[:project] ||= project
          opts[:api] = api
          Dataset.new(**opts)
        else
          raise ArgumentError, "dataset must be String, Hash, or Dataset, got #{dataset.class}"
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
