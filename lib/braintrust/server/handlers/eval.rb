# frozen_string_literal: true

require "json"

module Braintrust
  module Server
    module Handlers
      # POST /eval — adapter that maps HTTP request to Evaluator#run and streams SSE results.
      # Handles auth passthrough, datasets, remote scorers, project_id, and parent.
      class Eval
        def initialize(evaluators)
          @evaluators = evaluators
        end

        def call(env)
          body = parse_body(env)
          return error_response(400, "Invalid JSON body") unless body

          name = body["name"]
          return error_response(400, "Missing required field: name") unless name

          evaluator = @evaluators[name]
          return error_response(404, "Evaluator '#{name}' not found") unless evaluator

          data = body["data"]
          return error_response(400, "Missing required field: data") unless data

          # Validate exactly one data source
          data_sources = ["data", "dataset_name", "dataset_id"].count { |k| data.key?(k) }
          return error_response(400, "Exactly one data source required") if data_sources != 1

          experiment_name = body["experiment_name"]

          # Resolve data source
          cases, dataset = resolve_data_source(data)

          # Resolve remote scorers from request
          remote_scorer_ids = resolve_remote_scorers(body["scores"])

          # Resolve parent span context
          parent = resolve_parent(body["parent"])

          # Build state from auth context (if present)
          state = build_state(env)

          # The protocol-rack adapter (used by Falcon and any server built on
          # protocol-http) buffers `each`-based bodies through an Enumerable path.
          # Detect it via the "protocol.http.request" env key it injects, and use
          # SSEStreamBody (call-only) so it dispatches through the Streaming path.
          body_class = env.key?("protocol.http.request") ? SSEStreamBody : SSEBody

          sse_body = body_class.new do |sse|
            # Only pass project/experiment params when state is available
            run_opts = {
              on_progress: ->(progress_data) {
                # Build remote eval protocol events from generic progress data.
                # Runner provides: id, data/error, scores (optional), origin (optional).
                # Protocol requires: id, object_type, origin, name, format, output_type, event, data.
                base = {
                  "object_type" => "task",
                  "name" => name,
                  "format" => "code",
                  "output_type" => "completion"
                }
                base["id"] = progress_data["id"] if progress_data["id"]
                base["origin"] = progress_data["origin"] if progress_data["origin"]

                if progress_data.key?("error")
                  sse.event("progress", JSON.dump(base.merge("event" => "error", "data" => progress_data["error"])))
                else
                  sse.event("progress", JSON.dump(base.merge("event" => "json_delta", "data" => JSON.dump(progress_data["data"]))))
                end

                # Signal per-cell completion so the UI exits "Streaming..." state
                # and updates the progress bar immediately.
                sse.event("progress", JSON.dump(base.merge("event" => "done", "data" => "")))
              },
              quiet: true
            }
            run_opts[:parent] = parent if parent
            run_opts[:scorers] = remote_scorer_ids if remote_scorer_ids
            run_opts[:dataset] = dataset if dataset

            if state
              run_opts[:state] = state
              run_opts[:experiment] = experiment_name if experiment_name
              run_opts[:project_id] = body["project_id"] if body["project_id"]
            end

            result = evaluator.run(cases, **run_opts)

            # Flush buffered OTLP spans before sending completion events.
            # The BatchSpanProcessor exports every ~5s; fast evals can finish
            # before a single export fires, causing the UI to see no results.
            Braintrust::Trace.flush_spans

            # Build summary from result scores
            averaged_scores = {}
            result.scorer_stats.each do |scorer_name, stats|
              averaged_scores[scorer_name] = stats.score_mean
            end

            sse.event("summary", JSON.dump({
              "scores" => averaged_scores,
              "experiment_name" => experiment_name,
              "experiment_id" => result.experiment_id,
              "project_id" => result.project_id
            }))

            sse.event("done", "")
          end

          [200, {"content-type" => "text/event-stream", "cache-control" => "no-cache", "connection" => "keep-alive"}, sse_body]
        end

        private

        # Resolve data source from the data field.
        # Returns [cases, dataset] where exactly one is non-nil.
        def resolve_data_source(data)
          if data.key?("data")
            cases = data["data"].map do |d|
              {input: d["input"], expected: d["expected"]}
            end
            [cases, nil]
          elsif data.key?("dataset_id")
            [nil, Braintrust::DatasetId.new(id: data["dataset_id"])]
          elsif data.key?("dataset_name")
            dataset_opts = {name: data["dataset_name"]}
            dataset_opts[:project] = data["project_name"] if data["project_name"]
            [nil, dataset_opts]
          else
            [nil, nil]
          end
        end

        # Map request scores array to ScorerId structs.
        # The UI sends function_id as a nested object: {"function_id": "uuid"}.
        def resolve_remote_scorers(scores)
          return nil if scores.nil? || scores.empty?
          scores.map do |s|
            func_id = s["function_id"]
            func_id = func_id["function_id"] if func_id.is_a?(Hash)
            Braintrust::ScorerId.new(
              function_id: func_id,
              version: s["version"]
            )
          end
        end

        # Map request parent to symbol-keyed Hash.
        # Hardcode playground_id to match Java SDK behavior.
        # Also extracts generation from propagated_event for span_attributes.
        def resolve_parent(parent)
          return nil unless parent.is_a?(Hash)
          object_id = parent["object_id"]
          return nil unless object_id

          generation = parent.dig("propagated_event", "span_attributes", "generation")

          result = {object_type: "playground_id", object_id: object_id}
          result[:generation] = generation if generation
          result
        end

        # Build State from auth context set by Auth middleware.
        # Returns nil when no auth context is present (e.g. NoAuth strategy).
        # Uses an LRU-style cache (max 64 entries) keyed by [api_key, app_url, org_name].
        def build_state(env)
          auth = env["braintrust.auth"]
          return nil unless auth.is_a?(Hash)

          cache_key = [auth["api_key"], auth["app_url"], auth["org_name"]]

          @state_mutex ||= Mutex.new
          @state_cache ||= {}

          @state_mutex.synchronize do
            cached = @state_cache[cache_key]
            return cached if cached

            state = Braintrust::State.new(
              api_key: auth["api_key"],
              org_id: auth["org_id"],
              org_name: auth["org_name"],
              app_url: auth["app_url"],
              api_url: auth["api_url"],
              enable_tracing: false
            )

            # Evict oldest entry if cache is full
            if @state_cache.size >= 64
              oldest_key = @state_cache.keys.first
              @state_cache.delete(oldest_key)
            end

            @state_cache[cache_key] = state
            state
          end
        end

        def parse_body(env)
          body = env["rack.input"]&.read
          return nil if body.nil? || body.empty?
          JSON.parse(body)
        rescue JSON::ParserError
          nil
        end

        def error_response(status, message)
          [status, {"content-type" => "application/json"},
            [JSON.dump({"error" => message})]]
        end
      end
    end
  end
end
