# frozen_string_literal: true

require_relative "case"
require_relative "cases"
require_relative "scorer"
require_relative "result"
require_relative "../internal/thread_pool"

require "opentelemetry/sdk"
require "json"

module Braintrust
  module Eval
    # Internal runner class that performs the execution of the Eval and returns the result
    class Runner
      # Maximum parallelism allowed (mirrors Internal::ThreadPool::MAX_PARALLELISM)
      MAX_PARALLELISM = Internal::ThreadPool::MAX_PARALLELISM

      def initialize(experiment_id:, experiment_name:, project_id:, project_name:,
        task:, scorers:, state:, tracer_provider: nil)
        @experiment_id = experiment_id
        @experiment_name = experiment_name
        @project_id = project_id
        @project_name = project_name
        @task = task
        @scorers = normalize_scorers(scorers)
        @state = state
        @tracer_provider = tracer_provider || OpenTelemetry.tracer_provider
        @tracer = @tracer_provider.tracer("braintrust-eval")
        @parent_attr = "experiment_id:#{experiment_id}"
      end

      # Run evaluation and return Result
      # @param cases [Array, Enumerable] Test cases
      # @param parallelism [Integer] Number of parallel workers (default: 1)
      # @return [Result]
      def run(cases, parallelism: 1)
        start_time = Time.now
        normalized_cases = normalize_cases(cases)
        errors = Queue.new

        if parallelism && parallelism > 1
          Internal::ThreadPool.each(normalized_cases, parallelism: parallelism) do |test_case|
            run_case(test_case, errors)
          end
        else
          normalized_cases.each do |test_case|
            run_case(test_case, errors)
          end
        end

        # Convert Queue to Array after all threads complete
        error_array = [].tap { |a| a << errors.pop until errors.empty? }

        # Calculate duration
        duration = Time.now - start_time

        # Generate permalink
        permalink = "#{state.app_url}/app/#{state.org_name}/object?object_type=experiment&object_id=#{experiment_id}"

        Result.new(
          experiment_id: experiment_id,
          experiment_name: experiment_name,
          project_id: project_id,
          project_name: project_name,
          permalink: permalink,
          errors: error_array,
          duration: duration
        )
      end

      private

      attr_reader :experiment_id, :experiment_name, :project_id, :project_name,
        :task, :scorers, :state, :tracer, :parent_attr

      # Run a single test case with OpenTelemetry tracing
      # Creates eval span (parent) with task and score as children
      # @param test_case [Case] The test case
      # @param errors [Queue] Thread-safe error collection queue
      def run_case(test_case, errors)
        tracer.in_span("eval") do |eval_span|
          eval_span.set_attribute("braintrust.parent", parent_attr)

          # Set tags early so they're present even if task fails
          eval_span.set_attribute("braintrust.tags", test_case.tags) if test_case.tags

          # Run task
          output = nil
          begin
            output = run_task(test_case)
          rescue => e
            # Error already recorded on task span, set eval span status
            eval_span.status = OpenTelemetry::Trace::Status.error(e.message)
            errors << "Task failed for input '#{test_case.input}': #{e.message}"
            next
          end

          # Run scorers
          begin
            run_scorers(test_case, output)
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
      # @return [Object] Task output
      def run_task(test_case)
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
      def run_scorers(test_case, output)
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
            scorer
          else
            Scorer.new(scorer)
          end
        end
      end

      # Record error on span with exception event and error status
      # @param span [OpenTelemetry::Trace::Span] The span to record error on
      # @param error [Exception] The error that occurred
      # @param error_type [String] The error type name (optional)
      def record_span_error(span, error, error_type = nil)
        if error_type
          span.record_exception(error, attributes: {"exception.type" => error_type})
        else
          span.record_exception(error)
        end
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
