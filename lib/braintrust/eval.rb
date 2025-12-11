# frozen_string_literal: true

require_relative "eval/scorer"
require_relative "eval/runner"
require_relative "eval/summary"
require_relative "eval/result"
require_relative "internal/experiments"

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
      # @param send_logs [Boolean] If true (default), create experiment on server and send span data.
      #   If false, run evaluation locally without sending data to Braintrust.
      # @param state [State, nil] Braintrust state (defaults to global state)
      # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider (defaults to global)
      # @return [Result]
      def run(project:, experiment:, task:, scorers:,
        cases: nil, dataset: nil,
        parallelism: 1, tags: nil, metadata: nil, update: false, quiet: false,
        send_logs: true, state: nil, tracer_provider: nil)
        # Validate required parameters
        validate_params!(project: project, experiment: experiment,
          cases: cases, dataset: dataset, task: task, scorers: scorers)

        # Get state from parameter or global
        state ||= Braintrust.current_state
        raise Error, "No state available" unless state

        # Ensure state is logged in (to populate org_name, etc.)
        # login is idempotent and returns early if already logged in
        state.login

        # Resolve dataset to cases if dataset parameter provided
        if dataset
          cases = resolve_dataset(dataset, project, state)
        end

        if send_logs
          run_with_server(
            project: project, experiment: experiment, task: task, scorers: scorers,
            cases: cases, parallelism: parallelism, tags: tags, metadata: metadata,
            update: update, quiet: quiet, state: state, tracer_provider: tracer_provider
          )
        else
          run_local(
            project: project, experiment: experiment, task: task, scorers: scorers,
            cases: cases, parallelism: parallelism, quiet: quiet, state: state
          )
        end
      end

      private

      # Print result summary to stdout
      # @param result [Result] The evaluation result
      def print_result(result)
        puts result.to_pretty
      end

      # Run evaluation with server integration (send_logs: true)
      # Creates experiment, sends span data, fetches comparison summary
      def run_with_server(project:, experiment:, task:, scorers:, cases:,
        parallelism:, tags:, metadata:, update:, quiet:, state:, tracer_provider:)
        require_relative "api"

        # Register project and experiment via API
        reg_result = Internal::Experiments.get_or_create(
          experiment, project, state: state,
          tags: tags, metadata: metadata, update: update
        )

        experiment_id = reg_result[:experiment_id]
        project_id = reg_result[:project_id]
        project_name = reg_result[:project_name]

        # Generate permalink
        permalink = "#{state.app_url}/app/#{state.org_name}/object?object_type=experiment&object_id=#{experiment_id}"

        # Instantiate Runner and run evaluation with tracing
        runner = Runner.new(
          experiment_id: experiment_id,
          experiment_name: experiment,
          project_id: project_id,
          project_name: project_name,
          task: task,
          scorers: scorers,
          state: state,
          tracer_provider: tracer_provider
        )

        start_time = Time.now
        run_result = runner.run(cases, parallelism: parallelism)
        duration = Time.now - start_time

        # Fetch comparison summary from API
        # Note: If spans haven't been flushed yet, the API may return empty scores.
        # In that case, fetch_comparison_summary falls back to local raw_scores.
        summary = fetch_comparison_summary(
          experiment_id: experiment_id,
          experiment_name: experiment,
          project_name: project_name,
          permalink: permalink,
          duration: duration,
          errors: run_result.errors,
          raw_scores: run_result.scores,
          state: state
        )

        # Create result with summary
        result = Result.new(
          experiment_id: experiment_id,
          experiment_name: experiment,
          project_id: project_id,
          project_name: project_name,
          permalink: permalink,
          errors: run_result.errors,
          duration: duration,
          scores: run_result.scores,
          summary: summary
        )

        print_result(result) unless quiet
        result
      end

      # Run evaluation locally without server (send_logs: false)
      # No experiment created, no span data sent, local summary only
      def run_local(project:, experiment:, task:, scorers:, cases:,
        parallelism:, quiet:, state:)
        # Create a no-op tracer provider that doesn't send data
        no_op_tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

        # Instantiate Runner with no-op tracer (no data sent)
        runner = Runner.new(
          experiment_id: nil,
          experiment_name: experiment,
          project_id: nil,
          project_name: project,
          task: task,
          scorers: scorers,
          state: state,
          tracer_provider: no_op_tracer_provider
        )

        start_time = Time.now
        run_result = runner.run(cases, parallelism: parallelism)
        duration = Time.now - start_time

        # Build local summary from raw scores
        summary = ExperimentSummary.from_raw_scores(
          run_result.scores,
          {
            project_name: project,
            experiment_name: experiment,
            experiment_id: nil,
            experiment_url: nil,
            duration: duration,
            error_count: run_result.errors.length,
            errors: run_result.errors
          }
        )

        # Create result with local summary
        result = Result.new(
          experiment_id: nil,
          experiment_name: experiment,
          project_id: nil,
          project_name: project,
          permalink: nil,
          errors: run_result.errors,
          duration: duration,
          scores: run_result.scores,
          summary: summary
        )

        print_result(result) unless quiet
        result
      end

      # Fetch comparison summary from API, falling back to local on failure or empty response
      def fetch_comparison_summary(experiment_id:, experiment_name:, project_name:,
        permalink:, duration:, errors:, raw_scores:, state:)
        api = API.new(state: state)
        local_metadata = {
          project_name: project_name,
          experiment_name: experiment_name,
          experiment_id: experiment_id,
          experiment_url: permalink,
          duration: duration,
          error_count: errors.length,
          errors: errors
        }

        begin
          api_response = api.experiments.comparison(experiment_id: experiment_id)

          # If API returned empty scores, fall back to local data
          if api_response["scores"].nil? || api_response["scores"].empty?
            Log.debug("API returned no scores, using local summary")
            return ExperimentSummary.from_raw_scores(raw_scores, local_metadata)
          end

          build_server_summary(api_response, local_metadata)
        rescue => e
          Log.warn("Failed to fetch comparison summary: #{e.message}. Falling back to local summary.")
          ExperimentSummary.from_raw_scores(raw_scores, local_metadata)
        end
      end

      # Build ExperimentSummary from API response
      def build_server_summary(api_response, metadata)
        # Transform API scores into ScoreSummary objects
        scores = (api_response["scores"] || {}).map do |name, data|
          [name, ScoreSummary.new(
            name: name,
            score: data["score"],
            diff: data["diff"],
            improvements: data["improvements"],
            regressions: data["regressions"]
          )]
        end.to_h

        # Transform API metrics into MetricSummary objects
        metrics = (api_response["metrics"] || {}).map do |name, data|
          [name, MetricSummary.new(
            name: name,
            metric: data["metric"],
            unit: data["unit"] || "",
            diff: data["diff"]
          )]
        end.to_h

        # Build comparison info if present
        comparison = if api_response["comparisonExperimentName"]
          ComparisonInfo.new(
            baseline_experiment_id: api_response["comparisonExperimentId"],
            baseline_experiment_name: api_response["comparisonExperimentName"]
          )
        end

        ExperimentSummary.new(
          scores: scores,
          metrics: metrics.empty? ? nil : metrics,
          comparison: comparison,
          **metadata
        )
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

      # Resolve dataset parameter to an array of case records
      # @param dataset [String, Hash] Dataset specifier
      # @param project [String] Project name (used as default if not specified in hash)
      # @param state [State] Braintrust state
      # @return [Array<Hash>] Array of case records
      def resolve_dataset(dataset, project, state)
        require_relative "api"

        # Parse dataset parameter
        dataset_opts = case dataset
        when String
          # String: dataset name in same project
          {name: dataset, project: project}
        when Hash
          # Hash: explicit options
          dataset.dup
        else
          raise ArgumentError, "dataset must be String or Hash, got #{dataset.class}"
        end

        # Apply defaults
        dataset_opts[:project] ||= project

        # Create API client
        api = API.new(state: state)

        # Resolve dataset ID
        dataset_id = if dataset_opts[:id]
          # ID provided directly
          dataset_opts[:id]
        elsif dataset_opts[:name]
          # Fetch by name + project
          metadata = api.datasets.get(
            project_name: dataset_opts[:project],
            name: dataset_opts[:name]
          )
          metadata["id"]
        else
          raise ArgumentError, "dataset hash must specify either :name or :id"
        end

        # Fetch records with pagination
        limit_per_page = 1000
        max_records = dataset_opts[:limit]
        version = dataset_opts[:version]
        records = []
        cursor = nil

        loop do
          result = api.datasets.fetch(
            id: dataset_id,
            limit: limit_per_page,
            cursor: cursor,
            version: version
          )

          records.concat(result[:records])

          # Check if we've hit the user-specified limit
          if max_records && records.length >= max_records
            records = records.take(max_records)
            break
          end

          # Check if there's more data
          cursor = result[:cursor]
          break unless cursor
        end

        # Filter records to only include Case-compatible fields
        # Case accepts: input, expected, tags, metadata
        records.map do |record|
          filtered = {}
          filtered[:input] = record["input"] if record.key?("input")
          filtered[:expected] = record["expected"] if record.key?("expected")
          filtered[:tags] = record["tags"] if record.key?("tags")
          filtered[:metadata] = record["metadata"] if record.key?("metadata")
          filtered
        end
      end
    end
  end
end
