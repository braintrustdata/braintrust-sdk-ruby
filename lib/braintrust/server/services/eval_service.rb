# frozen_string_literal: true

require "json"

module Braintrust
  module Server
    module Services
      # Framework-agnostic service for running evaluations and streaming SSE results.
      # Must be long-lived (not per-request) to preserve the @state_cache across requests.
      class Eval
        def initialize(evaluators)
          @evaluators = evaluators
          @state_mutex = Mutex.new
          @state_cache = {}
        end

        # Validates request body. Returns:
        #   {error: String, status: Integer} on failure
        #   {evaluator:, name:, cases:, dataset:, ...} on success
        def validate(body)
          name = body["name"]
          return {error: "Missing required field: name", status: 400} unless name

          evaluator = current_evaluators[name]
          return {error: "Evaluator '#{name}' not found", status: 404} unless evaluator

          data = body["data"]
          return {error: "Missing required field: data", status: 400} unless data

          data_sources = ["data", "dataset_name", "dataset_id"].count { |k| data.key?(k) }
          return {error: "Exactly one data source required", status: 400} if data_sources != 1

          cases, dataset = resolve_data_source(data)

          {
            evaluator: evaluator,
            name: name,
            cases: cases,
            dataset: dataset,
            experiment_name: body["experiment_name"],
            remote_scorer_ids: resolve_remote_scorers(body["scores"]),
            parent: resolve_parent(body["parent"]),
            project_id: body["project_id"],
            parameters: resolve_parameters(body["parameters"], evaluator)
          }
        end

        # Runs the validated eval and streams SSE events via the sse writer.
        # +validated+ is the hash returned by #validate.
        # +auth+ is the auth context hash (or nil/true for no-auth).
        # +sse+ is an SSEWriter instance.
        def stream(validated, auth:, sse:)
          name = validated[:name]
          evaluator = validated[:evaluator]
          cases = validated[:cases]
          dataset = validated[:dataset]
          experiment_name = validated[:experiment_name]
          remote_scorer_ids = validated[:remote_scorer_ids]
          parent = validated[:parent]
          project_id = validated[:project_id]
          parameters = validated[:parameters]

          state = build_state(auth)

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
          run_opts[:parameters] = parameters if parameters && !parameters.empty?
          run_opts[:dataset] = dataset if dataset

          if state
            run_opts[:state] = state
            run_opts[:experiment] = experiment_name if experiment_name
            run_opts[:project_id] = project_id if project_id
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

        # Build State from auth context hash.
        # Returns nil when auth is not a Hash (e.g. NoAuth returns true).
        # Uses an LRU-style cache (max 64 entries) keyed by [api_key, app_url, org_name].
        def build_state(auth)
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

            if @state_cache.size >= 64
              oldest_key = @state_cache.keys.first
              @state_cache.delete(oldest_key)
            end

            @state_cache[cache_key] = state
            state
          end
        end

        private

        def current_evaluators
          return @evaluators.call if @evaluators.respond_to?(:call)
          @evaluators
        end

        # Merge request parameters with evaluator's parameter defaults.
        # Request values override defaults. Returns a string-keyed Hash.
        def resolve_parameters(raw_params, evaluator)
          defaults = (evaluator.parameters || {}).to_h { |name, spec|
            [name.to_s, spec.is_a?(Hash) ? (spec[:default] || spec["default"]) : nil]
          }.compact
          defaults.merge(raw_params || {})
        end

        # Resolve data source from the data field.
        # Returns [cases, dataset] where exactly one is non-nil.
        def resolve_data_source(data)
          if data.key?("data")
            cases = data["data"].map do |d|
              {input: d["input"], expected: d["expected"]}
            end
            [cases, nil]
          elsif data.key?("dataset_id")
            [nil, Braintrust::Dataset::ID.new(id: data["dataset_id"])]
          elsif data.key?("dataset_name")
            dataset_opts = {name: data["dataset_name"]}
            dataset_opts[:project] = data["project_name"] if data["project_name"]
            [nil, dataset_opts]
          else
            [nil, nil]
          end
        end

        # Map request scores array to Scorer::ID structs.
        # The UI sends function_id as a nested object: {"function_id": "uuid"}.
        def resolve_remote_scorers(scores)
          return nil if scores.nil? || scores.empty?
          scores.map do |s|
            func_id = s["function_id"]
            func_id = func_id["function_id"] if func_id.is_a?(Hash)
            Braintrust::Scorer::ID.new(
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
      end
    end
  end
end
