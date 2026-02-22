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
          data_sources = ["data", "datasetName", "datasetId"].count { |k| data.key?(k) }
          return error_response(400, "Exactly one data source required") if data_sources != 1

          experiment_name = body["experimentName"]

          # Resolve data source
          cases, dataset = resolve_data_source(data)

          # Resolve remote scorers from request
          remote_scorer_ids = resolve_remote_scorers(body["scores"])

          # Resolve parent span context
          parent = resolve_parent(body["parent"])

          # Build API client from auth context (if present)
          api = build_api(env)

          sse_body = SSEBody.new do |sse|
            # Only pass project/experiment params when API client is available
            run_opts = {
              on_progress: ->(progress_data) { sse.event("progress", JSON.dump(progress_data)) },
              quiet: true
            }
            run_opts[:parent] = parent if parent
            run_opts[:scorers] = remote_scorer_ids if remote_scorer_ids
            run_opts[:dataset] = dataset if dataset

            if api
              run_opts[:api] = api
              run_opts[:project] = body["projectName"] if body["projectName"]
              run_opts[:experiment] = experiment_name if experiment_name
              run_opts[:project_id] = body["projectId"] if body["projectId"]
              run_opts[:update] = true
            end

            result = evaluator.run(cases, **run_opts)

            # Build summary from result scores
            averaged_scores = {}
            result.scorer_stats.each do |scorer_name, stats|
              averaged_scores[scorer_name] = stats.score_mean
            end

            sse.event("summary", JSON.dump({
              "scores" => averaged_scores,
              "experimentName" => experiment_name,
              "experimentId" => result.experiment_id,
              "projectId" => result.project_id
            }))

            sse.event("done", "")
          end

          [200, {"content-type" => "text/event-stream"}, sse_body]
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
          elsif data.key?("datasetId")
            [nil, Braintrust::DatasetId.new(id: data["datasetId"])]
          elsif data.key?("datasetName")
            dataset_opts = {name: data["datasetName"]}
            dataset_opts[:project] = data["projectName"] if data["projectName"]
            [nil, dataset_opts]
          else
            [nil, nil]
          end
        end

        # Map request scores array to ScorerId structs
        def resolve_remote_scorers(scores)
          return nil if scores.nil? || scores.empty?
          scores.map do |s|
            Braintrust::ScorerId.new(
              function_id: s["function_id"] || s["functionId"],
              version: s["version"]
            )
          end
        end

        # Map request parent to symbol-keyed Hash
        def resolve_parent(parent)
          return nil unless parent.is_a?(Hash)
          {
            object_type: parent["object_type"] || parent["objectType"],
            object_id: parent["object_id"] || parent["objectId"]
          }
        end

        # Build API client from auth context set by Auth middleware.
        # Returns nil when no auth context is present (e.g. NoAuth strategy).
        def build_api(env)
          auth = env["braintrust.auth"]
          return nil unless auth.is_a?(Hash)

          state = Braintrust::State.new(
            api_key: auth["api_key"],
            org_id: auth["org_id"],
            org_name: auth["org_name"],
            app_url: auth["app_url"],
            api_url: auth["api_url"],
            enable_tracing: false
          )
          Braintrust::API.new(state: state)
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
