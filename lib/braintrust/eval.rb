# frozen_string_literal: true

require_relative "eval/case"
require_relative "eval/cases"
require_relative "eval/scorer"
require_relative "eval/result"
require_relative "internal/experiments"
require "opentelemetry/sdk"
require "json"

module Braintrust
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
      # @param parallelism [Integer] Number of parallel workers (default: 1)
      # @param tags [Array<String>] Optional experiment tags
      # @param metadata [Hash] Optional experiment metadata
      # @param update [Boolean] If true, allow reusing existing experiment (default: false)
      # @param quiet [Boolean] If true, suppress result output (default: false)
      # @param state [State, nil] Braintrust state (defaults to global state)
      # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider (defaults to global)
      # @return [Result]
      def run(project:, experiment:, task:, scorers:,
        cases: nil, dataset: nil,
        parallelism: 1, tags: nil, metadata: nil, update: false, quiet: false,
        state: nil, tracer_provider: nil)
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

        # Register project and experiment via API
        result = Internal::Experiments.get_or_create(
          experiment, project, state: state,
          tags: tags, metadata: metadata, update: update
        )

        experiment_id = result[:experiment_id]
        project_id = result[:project_id]
        project_name = result[:project_name]

        # Run the eval with resolved experiment info
        result = run_internal(
          experiment_id: experiment_id,
          experiment_name: experiment,
          project_id: project_id,
          project_name: project_name,
          cases: cases,
          task: task,
          scorers: scorers,
          state: state,
          tracer_provider: tracer_provider
        )

        # Print result summary unless quiet
        print_result(result) unless quiet

        result
      end

      private

      # Internal eval runner that doesn't touch the API
      # @param experiment_id [String] Resolved experiment ID
      # @param experiment_name [String] Experiment name
      # @param project_id [String] Resolved project ID
      # @param project_name [String] Project name
      # @param cases [Array, Enumerable, Cases] Test cases
      # @param task [#call] Task callable
      # @param scorers [Array] Scorers
      # @param state [State] Braintrust state
      # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider
      # @return [Result]
      def run_internal(experiment_id:, experiment_name:, project_id:, project_name:,
        cases:, task:, scorers:, state:, tracer_provider: nil)
        start_time = Time.now

        # Get tracer for creating spans
        tracer_provider ||= OpenTelemetry.tracer_provider
        tracer = tracer_provider.tracer("braintrust-eval")

        # Parent attribute for all eval spans
        parent_attr = "experiment_id:#{experiment_id}"

        # Normalize cases to Cases wrapper
        normalized_cases = normalize_cases(cases)

        # Normalize scorers to Scorer objects
        normalized_scorers = normalize_scorers(scorers)

        # Collect errors
        errors = []

        # Run each case with tracing
        normalized_cases.each do |test_case|
          run_case(test_case, task, normalized_scorers, errors,
            tracer, parent_attr)
        end

        # Calculate duration
        duration = Time.now - start_time

        # Generate permalink: {app_url}/app/{org}/object?object_type=experiment&object_id={experiment_id}
        permalink = "#{state.app_url}/app/#{state.org_name}/object?object_type=experiment&object_id=#{experiment_id}"

        # Return result
        Result.new(
          experiment_id: experiment_id,
          experiment_name: experiment_name,
          project_id: project_id,
          permalink: permalink,
          errors: errors,
          duration: duration
        )
      end

      # Print result summary to stdout
      # @param result [Result] The evaluation result
      def print_result(result)
        puts result
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

      # Normalize cases input to Cases wrapper
      # @param cases_input [Array, Enumerable, Cases] The cases input
      # @return [Cases]
      def normalize_cases(cases_input)
        case cases_input
        when Cases
          cases_input
        when Array, Enumerable
          Cases.new(cases_input)
        else
          if cases_input.respond_to?(:each)
            Cases.new(cases_input)
          else
            raise ArgumentError, "cases must be Array or Enumerable"
          end
        end
      end

      # Normalize scorers to Scorer objects
      # @param scorers_input [Array] The scorers input (Scorer objects or callables)
      # @return [Array<Scorer>]
      def normalize_scorers(scorers_input)
        scorers_input.map do |scorer|
          case scorer
          when Scorer
            # Already a Scorer
            scorer
          else
            # Wrap callable in Scorer (auto-detects name)
            Scorer.new(scorer)
          end
        end
      end

      # Run a single test case with OpenTelemetry tracing
      # Creates eval span (parent) with task and score as children
      # @param test_case [Case] The test case
      # @param task [#call] The task
      # @param scorers [Array<Scorer>] The scorers
      # @param errors [Array<String>] Error collection array
      # @param tracer [Tracer] OpenTelemetry tracer
      # @param parent_attr [String] Parent attribute (experiment_id:project/exp_id)
      def run_case(test_case, task, scorers, errors, tracer, parent_attr)
        # Create eval span (parent)
        tracer.in_span("eval") do |eval_span|
          eval_span.set_attribute("braintrust.parent", parent_attr)

          # Set tags early so they're present even if task fails
          eval_span.set_attribute("braintrust.tags", test_case.tags) if test_case.tags

          # Run task
          output = nil
          begin
            output = run_task(test_case, task, tracer, parent_attr)
          rescue => e
            # Error already recorded on task span, set eval span status
            eval_span.status = OpenTelemetry::Trace::Status.error(e.message)
            errors << "Task failed for input '#{test_case.input}': #{e.message}"
            next
          end

          # Run scorers
          begin
            run_scorers(test_case, output, scorers, tracer, parent_attr)
          rescue => e
            # Error already recorded on score span, set eval span status
            eval_span.status = OpenTelemetry::Trace::Status.error(e.message)
            errors << "Scorers failed for input '#{test_case.input}': #{e.message}"
          end

          # Set eval span attributes (after task and scorers complete)
          set_json_attr(eval_span, "braintrust.span_attributes", {type: "eval"})
          set_json_attr(eval_span, "braintrust.input_json", test_case.input)
          set_json_attr(eval_span, "braintrust.output_json", output)
          set_json_attr(eval_span, "braintrust.expected", test_case.expected) if test_case.expected
        end
      end

      # Run task with OpenTelemetry tracing
      # Creates task span with input and output
      # @param test_case [Case] The test case
      # @param task [#call] The task
      # @param tracer [Tracer] OpenTelemetry tracer
      # @param parent_attr [String] Parent attribute
      # @return [Object] Task output
      def run_task(test_case, task, tracer, parent_attr)
        tracer.in_span("task") do |task_span|
          task_span.set_attribute("braintrust.parent", parent_attr)
          set_json_attr(task_span, "braintrust.span_attributes", {type: "task"})
          set_json_attr(task_span, "braintrust.input_json", test_case.input)

          begin
            output = task.call(test_case.input)
            set_json_attr(task_span, "braintrust.output_json", output)
            output
          rescue => e
            # Record exception event with stacktrace, then set error status
            task_span.record_exception(e)
            task_span.status = OpenTelemetry::Trace::Status.error(e.message)
            raise
          end
        end
      end

      # Run scorers with OpenTelemetry tracing
      # Creates single score span for all scorers
      # @param test_case [Case] The test case
      # @param output [Object] Task output
      # @param scorers [Array<Scorer>] The scorers
      # @param tracer [Tracer] OpenTelemetry tracer
      # @param parent_attr [String] Parent attribute
      def run_scorers(test_case, output, scorers, tracer, parent_attr)
        tracer.in_span("score") do |score_span|
          score_span.set_attribute("braintrust.parent", parent_attr)
          set_json_attr(score_span, "braintrust.span_attributes", {type: "score"})

          scores = {}
          scorer_error = nil
          scorers.each do |scorer|
            score_value = scorer.call(test_case.input, test_case.expected, output, test_case.metadata || {})
            scores[scorer.name] = score_value
          rescue => e
            # Record first error but continue processing other scorers
            scorer_error ||= "Scorer '#{scorer.name}' failed: #{e.message}"
            record_span_error(score_span, e, "ScorerError")
          end

          # Always set scores attribute, even if some scorers failed
          set_json_attr(score_span, "braintrust.scores", scores)

          # Raise after setting scores so we can see which scorers succeeded
          raise scorer_error if scorer_error
        end
      end

      # Record error on span with exception event and error status
      # @param span [OpenTelemetry::Trace::Span] The span to record error on
      # @param error [Exception] The error that occurred
      # @param error_type [String] The error type name (optional, used for custom error classification)
      def record_span_error(span, error, error_type = nil)
        # Record exception with stacktrace (OpenTelemetry standard)
        if error_type
          # For custom error types, add type override
          span.record_exception(error, attributes: {"exception.type" => error_type})
        else
          span.record_exception(error)
        end

        # Set span status to error
        span.status = OpenTelemetry::Trace::Status.error(error.message)
      end

      # Set a span attribute by JSON encoding the value
      # @param span [OpenTelemetry::Trace::Span] The span
      # @param key [String] The attribute key
      # @param value [Object] The value to JSON encode
      def set_json_attr(span, key, value)
        span.set_attribute(key, JSON.dump(value))
      end
    end
  end
end
