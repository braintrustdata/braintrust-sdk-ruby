# frozen_string_literal: true

require_relative "case"
require_relative "result"
require_relative "summary"
require_relative "trace"
require_relative "../internal/thread_pool"
require_relative "../api/internal/btql"

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
        @tracer = eval_context.tracer_provider.tracer("braintrust-eval")

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
        # Each eval case starts its own trace — detach from any ambient span context
        eval_span = tracer.start_root_span("eval")
        OpenTelemetry::Trace.with_span(eval_span) do
          # Set attributes known before task execution
          eval_span.set_attribute("braintrust.parent", eval_context.parent_span_attr) if eval_context.parent_span_attr
          set_json_attr(eval_span, "braintrust.span_attributes", build_span_attributes("eval"))
          set_json_attr(eval_span, "braintrust.input_json", {input: case_context.input})
          set_json_attr(eval_span, "braintrust.expected", case_context.expected) if case_context.expected
          set_json_attr(eval_span, "braintrust.metadata", case_context.metadata) if case_context.metadata
          eval_span.set_attribute("braintrust.tags", case_context.tags) if case_context.tags
          eval_span.set_attribute("braintrust.origin", case_context.origin) if case_context.origin

          # Run task
          begin
            case_context.output = run_task(case_context)
          rescue => e
            # Error already recorded on task span, set eval span status
            eval_span.status = OpenTelemetry::Trace::Status.error(e.message)
            set_json_attr(eval_span, "braintrust.output_json", {output: nil})
            errors << "Task failed for input '#{case_context.input}': #{e.message}"
            report_progress(eval_span, case_context, error: e.message)
            next
          end

          # Flush spans so they're queryable via BTQL, then build trace
          eval_context.tracer_provider.force_flush if eval_context.tracer_provider.respond_to?(:force_flush)
          case_context.trace = build_trace(eval_span)

          # Run scorers
          begin
            run_scorers(case_context)
          rescue => e
            # Error already recorded on score span, set eval span status
            eval_span.status = OpenTelemetry::Trace::Status.error(e.message)
            errors << "Scorers failed for input '#{case_context.input}': #{e.message}"
          end

          # Set output after task completes
          set_json_attr(eval_span, "braintrust.output_json", {output: case_context.output})

          report_progress(eval_span, case_context, data: case_context.output)
        end
      ensure
        eval_span&.finish
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
            output = eval_context.task.call(
              input: case_context.input
            )
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

      # Run scorers with OpenTelemetry tracing.
      # Creates one span per scorer, each a direct child of the current (eval) span.
      # @param case_context [CaseContext] The per-case context (output must be populated)
      def run_scorers(case_context)
        scorer_kwargs = {
          input: case_context.input,
          expected: case_context.expected,
          output: case_context.output,
          metadata: case_context.metadata || {},
          trace: case_context.trace
        }
        scorer_input = {
          input: case_context.input,
          expected: case_context.expected,
          output: case_context.output,
          metadata: case_context.metadata || {}
        }

        scorer_error = nil
        eval_context.scorers.each do |scorer|
          collect_scores(run_scorer(scorer, scorer_kwargs, scorer_input))
        rescue => e
          scorer_error ||= e
        end

        raise scorer_error if scorer_error
      end

      # Run a single scorer inside its own span.
      # @param scorer [Scorer] The scorer to run
      # @param scorer_kwargs [Hash] Keyword arguments for the scorer
      # @param scorer_input [Hash] Input to log on the span
      # @return [Array<Hash>] Raw score results from the scorer
      def run_scorer(scorer, scorer_kwargs, scorer_input)
        tracer.in_span(scorer.name) do |score_span|
          score_span.set_attribute("braintrust.parent", eval_context.parent_span_attr) if eval_context.parent_span_attr
          set_json_attr(score_span, "braintrust.span_attributes", build_scorer_span_attributes(scorer.name))
          set_json_attr(score_span, "braintrust.input_json", scorer_input)

          score_results = scorer.call(**scorer_kwargs)

          scorer_scores = {}
          scorer_metadata = {}
          score_results.each do |s|
            scorer_scores[s[:name]] = s[:score]
            scorer_metadata[s[:name]] = s[:metadata] if s[:metadata].is_a?(Hash)
          end

          set_json_attr(score_span, "braintrust.output_json", scorer_scores)
          set_json_attr(score_span, "braintrust.scores", scorer_scores)
          set_json_attr(score_span, "braintrust.metadata", scorer_metadata) unless scorer_metadata.empty?

          score_results
        rescue => e
          record_span_error(score_span, e, "ScorerError")
          raise
        end
      end

      # Build a lazy Trace for a case, backed by BTQL.
      # Returns nil when state or experiment_id are unavailable (local-only mode).
      # @param eval_span [OpenTelemetry::Trace::Span] The eval span for this case
      # @return [Eval::Trace, nil]
      def build_trace(eval_span)
        return nil unless eval_context.state && eval_context.experiment_id

        root_span_id = eval_span.context.hex_trace_id
        object_type = "experiment"
        object_id = eval_context.experiment_id
        btql = API::Internal::BTQL.new(eval_context.state)

        Eval::Trace.new(
          spans: -> { btql.trace_spans(object_type: object_type, object_id: object_id, root_span_id: root_span_id) }
        )
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

      # Report progress for a case via on_progress callback.
      # Rescues errors in the callback so a broken handler never crashes the eval.
      def report_progress(eval_span, case_context, **fields)
        return unless eval_context.on_progress
        progress = {"id" => eval_span.context.hex_span_id}.merge(fields.transform_keys(&:to_s))
        if case_context.origin
          progress["origin"] = case_context.origin.is_a?(String) ? JSON.parse(case_context.origin) : case_context.origin
        end
        eval_context.on_progress.call(progress)
      rescue => e
        Braintrust.logger.warn("on_progress callback error: #{e.message}")
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

      # Build span_attributes for a scorer span.
      # Each scorer gets its own span with type "score", purpose "scorer", and the scorer's name.
      # @param scorer_name [String] The scorer name
      # @return [Hash]
      def build_scorer_span_attributes(scorer_name)
        attrs = {type: "score", name: scorer_name, purpose: "scorer"}
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

      # Collect score results into the summary accumulator (thread-safe).
      # @param score_results [Array<Hash>] Score results from a scorer
      def collect_scores(score_results)
        @score_mutex.synchronize do
          score_results.each { |s| (@scores[s[:name]] ||= []) << s[:score] }
        end
      end
    end
  end
end
