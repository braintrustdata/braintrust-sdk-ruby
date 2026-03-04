# frozen_string_literal: true

require_relative "case"
require_relative "result"
require_relative "summary"
require_relative "../internal/thread_pool"

require "opentelemetry/sdk"
require "json"

module Braintrust
  module Eval
    # Internal runner class that performs the execution of the Eval and returns the result.
    # Receives a fully-normalized Context — all callables are already typed wrappers.
    class Runner
      # Maximum parallelism allowed (mirrors Internal::ThreadPool::MAX_PARALLELISM)
      MAX_PARALLELISM = Internal::ThreadPool::MAX_PARALLELISM

      # Per-case mutable accumulator. Built from Case, populated by task and scoring stages.
      CaseContext = Struct.new(:input, :expected, :output, :metadata, :tags, :trace, :origin, keyword_init: true)

      # @param eval_context [Context] Normalized eval context
      def initialize(eval_context)
        @eval_context = eval_context
        tracer_provider = eval_context.tracer_provider || OpenTelemetry.tracer_provider
        @tracer = tracer_provider.tracer("braintrust-eval")

        # Mutex for thread-safe score collection
        @score_mutex = Mutex.new
      end

      # Run evaluation and return Result
      # @param parallelism [Integer] Number of parallel workers (default: 1)
      # @return [Result]
      def run(parallelism: 1)
        start_time = Time.now
        eval_cases = eval_context.cases
        errors = Queue.new
        @scores = {} # Reset for each run: { scorer_name => Array<Numeric> }

        if parallelism && parallelism > 1
          Internal::ThreadPool.each(eval_cases, parallelism: parallelism) do |eval_case|
            run_eval_case(build_case_context(eval_case), errors)
          end
        else
          eval_cases.each do |eval_case|
            run_eval_case(build_case_context(eval_case), errors)
          end
        end

        # Convert Queue to Array after all threads complete
        error_array = [].tap { |a| a << errors.pop until errors.empty? }

        # Calculate duration
        duration = Time.now - start_time

        # Generate permalink (only when state and experiment are available)
        permalink = if eval_context.state && eval_context.experiment_id
          eval_context.state.object_permalink(object_type: "experiment", object_id: eval_context.experiment_id)
        end

        Result.new(
          experiment_id: eval_context.experiment_id,
          experiment_name: eval_context.experiment_name,
          project_id: eval_context.project_id,
          project_name: eval_context.project_name,
          permalink: permalink,
          errors: error_array,
          duration: duration,
          scores: @scores
        )
      end

      private

      attr_reader :eval_context, :tracer

      # Run a single test case with OpenTelemetry tracing
      # Creates eval span (parent) with task and score as children
      # @param case_context [CaseContext] The per-case accumulator
      # @param errors [Queue] Thread-safe error collection queue
      def run_eval_case(case_context, errors)
        tracer.in_span("eval") do |eval_span|
          eval_span.set_attribute("braintrust.parent", eval_context.parent_span_attr) if eval_context.parent_span_attr

          # Set tags early so they're present even if task fails
          eval_span.set_attribute("braintrust.tags", case_context.tags) if case_context.tags

          # Run task
          begin
            case_context.output = run_task(case_context)
          rescue => e
            # Error already recorded on task span, set eval span status
            eval_span.status = OpenTelemetry::Trace::Status.error(e.message)
            errors << "Task failed for input '#{case_context.input}': #{e.message}"
            report_progress(eval_span, case_context, error: e.message)
            next
          end

          # Run scorers
          case_scores = nil
          begin
            case_scores = run_scorers(case_context)
          rescue => e
            # Error already recorded on score span, set eval span status
            eval_span.status = OpenTelemetry::Trace::Status.error(e.message)
            errors << "Scorers failed for input '#{case_context.input}': #{e.message}"
          end

          # Set eval span attributes (after task and scorers complete)
          set_json_attr(eval_span, "braintrust.span_attributes", build_span_attributes("eval"))
          set_json_attr(eval_span, "braintrust.input_json", case_context.input)
          set_json_attr(eval_span, "braintrust.output_json", case_context.output)
          set_json_attr(eval_span, "braintrust.expected", case_context.expected) if case_context.expected

          # Set origin for cases from remote sources (already JSON-serialized)
          eval_span.set_attribute("braintrust.origin", case_context.origin) if case_context.origin

          report_progress(eval_span, case_context, data: case_context.output, scores: case_scores || {})
        end
      end

      # Run task with OpenTelemetry tracing
      # Creates task span with input and output
      # @param case_context [CaseContext] The per-case context
      # @return [Object] Task output
      def run_task(case_context)
        tracer.in_span("task") do |task_span|
          task_span.set_attribute("braintrust.parent", eval_context.parent_span_attr) if eval_context.parent_span_attr
          set_json_attr(task_span, "braintrust.span_attributes", build_span_attributes("task"))
          set_json_attr(task_span, "braintrust.input_json", case_context.input)

          begin
            output = eval_context.task.call(build_task_args(case_context))
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
      # @param case_context [CaseContext] The per-case context (output must be populated)
      # @return [Hash] Scores hash { scorer_name => score_value }
      def run_scorers(case_context)
        tracer.in_span("score") do |score_span|
          score_span.set_attribute("braintrust.parent", eval_context.parent_span_attr) if eval_context.parent_span_attr
          set_json_attr(score_span, "braintrust.span_attributes", build_span_attributes("score"))

          scorer_args = build_scorer_args(case_context)
          scores = {}
          scorer_error = nil
          eval_context.scorers.each do |scorer|
            score_value = scorer.call(scorer_args)
            scores[scorer.name] = score_value

            # Collect raw score for summary (thread-safe)
            collect_score(scorer.name, score_value)
          rescue => e
            # Record first error but continue processing other scorers
            scorer_error ||= e
            record_span_error(score_span, e, "ScorerError")
          end

          # Always set scores attribute, even if some scorers failed
          set_json_attr(score_span, "braintrust.scores", scores)

          # Raise after setting scores so we can see which scorers succeeded
          raise scorer_error if scorer_error

          scores
        end
      end

      # Build a CaseContext from a Case struct
      # @param eval_case [Case] The eval case
      # @return [CaseContext]
      def build_case_context(eval_case)
        CaseContext.new(
          input: eval_case.input, expected: eval_case.expected,
          metadata: eval_case.metadata, tags: eval_case.tags, origin: eval_case.origin
        )
      end

      # Build Task::Args from a CaseContext
      # @param case_context [CaseContext] The per-case context
      # @return [Task::Args]
      def build_task_args(case_context)
        Task::Args.new(
          input: case_context.input,
          metadata: case_context.metadata || {},
          tags: case_context.tags
        )
      end

      # Build Scorer::Args from a CaseContext
      # @param case_context [CaseContext] The per-case context
      # @return [Scorer::Args]
      def build_scorer_args(case_context)
        Scorer::Args.new(
          input: case_context.input, expected: case_context.expected, output: case_context.output,
          metadata: case_context.metadata || {}, tags: case_context.tags
        )
      end

      # Report progress for a case via on_progress callback
      def report_progress(eval_span, case_context, **fields)
        return unless eval_context.on_progress
        progress = {"id" => eval_span.context.hex_span_id}.merge(fields.transform_keys(&:to_s))
        if case_context.origin
          progress["origin"] = case_context.origin.is_a?(String) ? JSON.parse(case_context.origin) : case_context.origin
        end
        eval_context.on_progress.call(progress)
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

      # Build span_attributes hash with type, and optionally name and generation.
      # Matches Java SDK behavior of including these on every span.
      # @param type [String] Span type ("eval", "task", or "score")
      # @return [Hash]
      def build_span_attributes(type)
        attrs = {type: type}
        attrs[:name] = eval_context.experiment_name if eval_context.experiment_name
        attrs[:generation] = eval_context.generation if eval_context.generation
        attrs
      end

      # Set a span attribute by JSON encoding the value
      # @param span [OpenTelemetry::Trace::Span] The span
      # @param key [String] The attribute key
      # @param value [Object] The value to JSON encode
      def set_json_attr(span, key, value)
        span.set_attribute(key, JSON.dump(value))
      end

      # Collect a single score value for summary calculation
      # @param name [String] Scorer name
      # @param value [Object] Score value (only Numeric values are collected)
      def collect_score(name, value)
        return unless value.is_a?(Numeric)

        @score_mutex.synchronize do
          (@scores[name] ||= []) << value
        end
      end
    end
  end
end
