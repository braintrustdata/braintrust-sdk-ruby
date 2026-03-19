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
          @service = Services::Eval.new(evaluators)
        end

        def call(env)
          body = parse_body(env)
          return error_response(400, "Invalid JSON body") unless body

          result = @service.validate(body)
          return error_response(result[:status], result[:error]) if result[:error]

          # The protocol-rack adapter (used by Falcon and any server built on
          # protocol-http) buffers `each`-based bodies through an Enumerable path.
          # Detect it via the "protocol.http.request" env key it injects, and use
          # SSEStreamBody (call-only) so it dispatches through the Streaming path.
          body_class = env.key?("protocol.http.request") ? SSEStreamBody : SSEBody

          sse_body = body_class.new do |sse|
            @service.stream(result, auth: env["braintrust.auth"], sse: sse)
          end

          [200, {"content-type" => "text/event-stream", "cache-control" => "no-cache", "connection" => "keep-alive"}, sse_body]
        end

        private

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

        def build_state(env)
          @service.build_state(env["braintrust.auth"])
        end
      end
    end
  end
end
