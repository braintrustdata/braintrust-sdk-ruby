# frozen_string_literal: true

require "json"
require "securerandom"
require "net/http"
require "uri"
require "time"

module Braintrust
  module Remote
    # Runs evaluations for remote/playground mode and collects results
    class EvalRunner
      attr_reader :evaluator, :state, :parameters

      def initialize(evaluator, state:, parameters: {}, stream_callback: nil, on_start: nil, no_send_logs: false, dataset_id: nil, parent: nil)
        @evaluator = evaluator
        @state = state
        @raw_parameters = parameters
        @stream_callback = stream_callback
        @on_start = on_start
        @no_send_logs = no_send_logs
        @dataset_id = dataset_id
        @parent = parent
        @parameters = validate_and_build_parameters(parameters)
        @pending_spans = [] # Collect spans to log to parent
      end

      # Run the evaluation
      # @param data [Array<EvalCase>, nil] Override data (from playground)
      # @param extra_scorers [Array] Additional scorers from playground
      # @param experiment_name [String, nil] Override experiment name
      # @param project_id [String, nil] Project ID
      # @return [Hash] Evaluation summary
      def run(data: nil, extra_scorers: [], experiment_name: nil, project_id: nil)
        eval_data = data || @evaluator.resolve_data
        all_scorers = @evaluator.scorers + extra_scorers

        # Create experiment only if we have a state AND we're not in no_send_logs mode
        # When running from the playground (no_send_logs=true), the playground manages experiments
        experiment = nil
        if @state && !@no_send_logs
          begin
            experiment = create_experiment(
              project: project_id || @evaluator.project_name,
              name: experiment_name || @evaluator.experiment_name
            )
          rescue => e
            Log.debug("[RUNNER] Failed to create experiment (running locally): #{e.message}")
            # Continue without experiment - run locally
          end
        end

        # When running from playground (no_send_logs), don't include project_id in summary
        # This matches Python's behavior where projectId is null in playground mode
        summary_project_id = @no_send_logs ? nil : project_id
        summary = build_initial_summary(experiment, eval_data, summary_project_id)

        # Only call on_start if we created an experiment (matching Python/TS behavior)
        # When running from the playground (with parent), the playground handles start events
        if experiment && @on_start
          Log.debug("[RUNNER] Experiment created, calling on_start...")
          @on_start.call(summary)
        end

        results = []
        Log.info("[RUNNER] Processing #{eval_data.length} eval cases...")

        eval_data.each_with_index do |eval_case, idx|
          Log.debug("[RUNNER] Running case #{idx + 1}/#{eval_data.length}: input=#{eval_case.input.to_s[0..50]}...")
          result = run_single(eval_case, all_scorers, idx)
          results << result
          Log.debug("[RUNNER] Case #{idx + 1} complete: output=#{result[:output].to_s[0..50]}...")
        end

        Log.debug("[RUNNER] All cases complete, building final summary...")

        # Log spans to parent if we have one
        if @parent && @state && @pending_spans.any?
          flush_spans_to_parent
        end

        final_summary = build_final_summary(summary, results)
        Log.info("[RUNNER] Complete. Scores: #{final_summary[:scores].keys.join(", ")}")
        final_summary
      end

      def flush_spans_to_parent
        return unless @parent && @pending_spans.any?

        Log.debug("[RUNNER] Parent object: #{@parent.inspect}")
        Log.debug("[RUNNER] Flushing #{@pending_spans.length} spans to parent...")

        begin
          log_spans_to_api(@pending_spans)
          Log.debug("[RUNNER] Successfully logged #{@pending_spans.length} spans")
        rescue => e
          Log.error("[RUNNER] Error logging spans: #{e.message}")
          Log.debug("[RUNNER] #{e.backtrace.first(3).join("\n")}") if e.backtrace
        ensure
          @pending_spans = []
        end
      end

      private

      def validate_and_build_parameters(raw_params)
        definitions = @evaluator.parameter_definitions
        return {} if definitions.empty?

        validated = {}
        definitions.each do |name, definition|
          value = raw_params[name] || raw_params[name.to_s]
          validated[name] = definition.validate(value)
        end
        validated
      end

      def run_single(eval_case, scorers, index)
        Log.debug("[RUNNER] run_single #{index}: Creating hooks...")

        # Generate unique IDs for this eval case
        row_id = SecureRandom.uuid
        span_id = SecureRandom.uuid
        root_span_id = extract_root_span_id || span_id

        hooks = EvalHooks.new(
          parameters: @parameters,
          metadata: eval_case.metadata&.dup || {},
          stream_callback: @stream_callback
        )

        output = nil
        error = nil
        start_time = Time.now.utc

        begin
          Log.debug("[RUNNER] run_single #{index}: Calling task with input: #{eval_case.input.to_s[0..50]}...")
          output = @evaluator.run_task(eval_case.input, hooks)
          Log.debug("[RUNNER] run_single #{index}: Task returned: #{output.to_s[0..50]}...")

          # Report task completion with proper format matching Python
          # Include origin field with dataset row info
          @stream_callback&.call({
            id: row_id,
            origin: build_origin(eval_case),
            name: @evaluator.name,
            object_type: "task",
            format: "code",
            output_type: "completion",
            event: "json_delta",
            data: output.to_json
          })
        rescue => e
          Log.error("[RUNNER] run_single #{index}: Task error: #{e.message}")
          Log.debug("[RUNNER] #{e.backtrace.first(3).join("\n")}") if e.backtrace
          error = e.message

          # Report error with origin
          @stream_callback&.call({
            id: row_id,
            origin: build_origin(eval_case),
            name: @evaluator.name,
            object_type: "task",
            format: "code",
            output_type: "completion",
            event: "error",
            data: e.message
          })
        end

        # Run scorers
        Log.debug("[RUNNER] run_single #{index}: Running #{scorers.length} scorers...")
        scores = run_scorers(scorers, eval_case, output, error, row_id)
        Log.debug("[RUNNER] run_single #{index}: Scores: #{scores.keys.join(", ")}")

        # Create span event for logging to parent
        if @parent
          span_event = build_span_event(
            row_id: row_id,
            span_id: span_id,
            root_span_id: root_span_id,
            eval_case: eval_case,
            output: output,
            error: error,
            scores: scores,
            metadata: hooks.metadata,
            start_time: start_time
          )
          @pending_spans << span_event
        end

        {
          index: index,
          input: eval_case.input,
          output: output,
          expected: eval_case.expected,
          error: error,
          scores: scores,
          metadata: hooks.metadata
        }
      end

      def extract_root_span_id
        return nil unless @parent

        @parent.dig("row_ids", "root_span_id")
      end

      def build_span_event(row_id:, span_id:, root_span_id:, eval_case:, output:, error:, scores:, metadata:, start_time:)
        end_time = Time.now.utc

        # Build span_attributes - MUST include propagated_event data for playground correlation!
        span_attrs = {name: "eval", type: "eval"}

        # Merge in propagated_event span_attributes (critical for playground correlation!)
        if @parent && @parent["propagated_event"]
          propagated_attrs = @parent.dig("propagated_event", "span_attributes")
          span_attrs.merge!(propagated_attrs.transform_keys(&:to_sym)) if propagated_attrs
        end

        event = {
          :id => row_id,
          :span_id => span_id,
          :root_span_id => root_span_id,
          :span_parents => extract_parent_span_ids,
          "_is_merge" => false,
          :span_attributes => span_attrs,
          :input => eval_case.input,
          :output => output,
          :expected => eval_case.expected,
          :scores => format_scores_for_span(scores),
          :metadata => metadata,
          :error => error,
          :origin => build_origin(eval_case),
          :created => start_time.iso8601(3),
          :metrics => {
            start: start_time.to_f,
            end: end_time.to_f
          }
        }

        # Add object_type and object_id from parent for /logs3 routing
        if @parent
          log_id = case @parent["object_type"]
          when "playground_logs" then "x"
          when "project_logs" then "g"
          when "experiment" then "e"
          else "x"
          end

          event[:log_id] = log_id

          case @parent["object_type"]
          when "playground_logs"
            event[:prompt_session_id] = @parent["object_id"]
          when "project_logs"
            event[:project_id] = @parent["object_id"]
          when "experiment"
            event[:experiment_id] = @parent["object_id"]
          end
        end

        # Add tags if present
        event[:tags] = eval_case.tags if eval_case.respond_to?(:tags) && eval_case.tags

        event.compact
      end

      def extract_parent_span_ids
        return nil unless @parent

        parent_span_id = @parent.dig("row_ids", "span_id")
        parent_span_id ? [parent_span_id] : nil
      end

      def format_scores_for_span(scores)
        return {} unless scores

        scores.transform_values do |score_data|
          if score_data.is_a?(Hash)
            score_data[:score]
          else
            score_data
          end
        end
      end

      def run_scorers(scorers, eval_case, output, error, case_id = nil)
        return {} if error

        scores = {}
        scorers.each_with_index do |scorer, idx|
          name = scorer_name(scorer, idx)
          begin
            score = run_scorer(scorer, eval_case, output)
            scores[name] = normalize_score(score)

            # Stream score completion
            if @stream_callback && case_id
              @stream_callback.call({
                id: case_id,
                object_type: "scorer",
                name: name,
                format: "code",
                output_type: "score",
                event: "json_delta",
                data: scores[name].to_json
              })
            end
          rescue => e
            scores[name] = {score: nil, error: e.message}
          end
        end
        scores
      end

      def run_scorer(scorer, eval_case, output)
        args = {
          input: eval_case.input,
          output: output,
          expected: eval_case.expected,
          metadata: eval_case.metadata
        }

        if scorer.respond_to?(:call)
          # Check arity to determine call style (only for Proc/Lambda that respond to arity)
          if scorer.respond_to?(:arity)
            if scorer.arity == 1 || (scorer.arity < 0 && scorer.parameters.any? { |p| p[0] == :keyreq })
              # Keyword arguments style
              scorer.call(**args)
            else
              # Positional arguments style
              scorer.call(eval_case.input, output, eval_case.expected)
            end
          else
            # For objects with #call but no #arity (like InlineScorer), use keyword args
            scorer.call(**args)
          end
        elsif scorer.respond_to?(:score)
          scorer.score(**args)
        else
          raise Braintrust::Error, "Invalid scorer: must respond to #call or #score"
        end
      end

      def normalize_score(result)
        case result
        when Numeric
          {score: result.to_f}
        when Hash
          result.transform_keys(&:to_sym)
        when true
          {score: 1.0}
        when false
          {score: 0.0}
        else
          {score: result.to_f}
        end
      end

      def scorer_name(scorer, index)
        ScorerUtils.extract_name(scorer, index)
      end

      def build_origin(eval_case)
        return nil unless @dataset_id

        origin = {
          object_type: "dataset",
          object_id: @dataset_id,
          id: eval_case.id || SecureRandom.uuid,
          created: eval_case.created || Time.now.utc.iso8601(3)
        }

        if eval_case.metadata&.dig("_xact_id")
          origin[:_xact_id] = eval_case.metadata["_xact_id"]
        end

        origin
      end

      def build_initial_summary(experiment, data, project_id = nil)
        # Internal::Experiments.get_or_create returns flat hash with symbol keys:
        # {experiment_id:, experiment_name:, project_id:, project_name:}
        {
          experimentName: experiment&.dig(:experiment_name) || @evaluator.name,
          projectName: experiment&.dig(:project_name) || @evaluator.project_name || @evaluator.name,
          experimentId: experiment&.dig(:experiment_id),
          projectId: experiment&.dig(:project_id) || project_id,
          projectUrl: nil,
          experimentUrl: nil,
          comparisonExperimentName: nil,
          scores: {},
          metrics: {}
        }
      end

      def build_final_summary(summary, results)
        # Aggregate scores
        score_totals = Hash.new { |h, k| h[k] = {sum: 0.0, count: 0} }

        results.each do |result|
          result[:scores]&.each do |name, score_data|
            next unless score_data[:score]

            score_totals[name][:sum] += score_data[:score]
            score_totals[name][:count] += 1
          end
        end

        # Format scores
        summary[:scores] = score_totals.transform_values do |data|
          {
            name: data[:name] || "score",
            score: (data[:count] > 0) ? data[:sum] / data[:count] : 0.0,
            improvements: 0,
            regressions: 0,
            diff: nil
          }
        end

        # Add name and _longest_score_name to each score
        longest_name_length = summary[:scores].keys.map { |k| k.to_s.length }.max || 0
        summary[:scores].each do |name, score_data|
          score_data[:name] = name.to_s
          score_data[:_longest_score_name] = longest_name_length
        end

        # Include individual results for sync mode
        summary[:results] = results.map do |result|
          {
            input: result[:input],
            output: result[:output],
            expected: result[:expected],
            error: result[:error],
            scores: result[:scores],
            metadata: result[:metadata]
          }
        end

        summary
      end

      def create_experiment(project:, name: nil)
        # Use the existing Internal::Experiments API
        Internal::Experiments.get_or_create(
          name || @evaluator.experiment_name || "#{@evaluator.name}-eval",
          project,
          state: @state
        )
      end

      def log_spans_to_api(events)
        # Ensure we have api_url
        @state.login unless @state.logged_in

        api_url = @state.api_url
        return unless api_url

        uri = URI.parse("#{api_url}/logs3")
        Log.debug("[RUNNER] Logging #{events.length} spans to #{uri}")

        # Python's format: rows is an array of JSON strings, not objects
        rows_as_strings = events.map { |e| e.to_json }

        # Build the payload string directly like Python does
        rows_json = "[" + rows_as_strings.join(",") + "]"
        payload_str = '{"rows": ' + rows_json + ', "api_version": 2}'

        Log.debug("[RUNNER] Payload preview: #{payload_str[0..200]}...")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 30
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@state.api_key}"
        request["x-bt-org-name"] = @state.org_name if @state.org_name
        request.body = payload_str

        response = http.request(request)
        Log.debug("[RUNNER] Response status: #{response.code}")
        Log.debug("[RUNNER] Response body: #{response.body.to_s[0..200]}") if response.body

        response
      end
    end
  end
end
