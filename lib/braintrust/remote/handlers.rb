# frozen_string_literal: true

require "json"

module Braintrust
  module Remote
    # Request/response handlers for evaluation server endpoints
    #
    # This module contains the business logic for the `/list` and `/eval` endpoints.
    # The handlers are framework-agnostic - they take parsed request data and return
    # response data, without any dependency on Rack or Rails.
    #
    # @example Use in a Rack app
    #   post "/eval" do
    #     body = JSON.parse(request.body.read)
    #     result = Handlers.run_eval(
    #       evaluators: @evaluators,
    #       context: ctx,
    #       body: body
    #     )
    #     [result[:status], result[:headers], [result[:body].to_json]]
    #   end
    #
    # @example Use in Rails controller
    #   def eval
    #     result = Braintrust::Remote::Handlers.run_eval(
    #       evaluators: Braintrust::Remote.evaluators,
    #       context: @braintrust_context,
    #       body: params.to_unsafe_h
    #     )
    #     render json: result[:body], status: result[:status]
    #   end
    #
    module Handlers
      # Prepare and validate an eval request
      #
      # This method handles the common validation logic for eval requests:
      # - Checks authorization
      # - Parses JSON body
      # - Determines streaming mode
      #
      # @param context [RequestContext, nil] The authenticated request context
      # @param body_json [String] Raw JSON body string
      # @return [Hash] Result hash with either:
      #   - `{ok: true, body: Hash, stream: Boolean}` on success
      #   - `{ok: false, error: String, status: Integer}` on failure
      #
      # @example In a Rack app
      #   result = Handlers.prepare_request(
      #     context: env["braintrust.context"],
      #     body_json: request.body.read
      #   )
      #
      #   unless result[:ok]
      #     return [result[:status], {"Content-Type" => "application/json"}, [{error: result[:error]}.to_json]]
      #   end
      #
      #   if result[:stream]
      #     run_streaming_eval(result[:body])
      #   else
      #     run_sync_eval(result[:body])
      #   end
      #
      # @example In a Rails controller
      #   result = Handlers.prepare_request(
      #     context: @braintrust_context,
      #     body_json: request.raw_post
      #   )
      #
      #   unless result[:ok]
      #     return render json: {error: result[:error]}, status: result[:status]
      #   end
      #
      def self.prepare_request(context:, body_json:)
        # Check authorization
        unless context&.authorized?
          Braintrust::Log.warn("[Handlers] Unauthorized request")
          return {ok: false, error: "Unauthorized", status: 401}
        end

        # Parse body
        begin
          body = JSON.parse(body_json)
        rescue JSON::ParserError => e
          Braintrust::Log.warn("[Handlers] Invalid JSON: #{e.message}")
          return {ok: false, error: "Invalid JSON", status: 400}
        end

        # Determine streaming mode
        stream = body["stream"] == true

        Braintrust::Log.debug("[Handlers] Request prepared: stream=#{stream}")
        {ok: true, body: body, stream: stream}
      end

      # Handle the /list endpoint
      #
      # Returns a hash of evaluators with their parameters and scorers.
      #
      # @param evaluators [Hash<String, Evaluator>] Map of name -> evaluator
      # @return [Hash] Response with evaluator info
      #
      # @example
      #   result = Handlers.list_evaluators(Braintrust::Remote.evaluators)
      #   # => { "My Eval" => { parameters: {...}, scores: [...] }, ... }
      #
      def self.list_evaluators(evaluators)
        Braintrust::Log.debug("[Handlers] Listing #{evaluators.length} evaluators")
        ServerHelpers.format_evaluator_list(evaluators)
      end

      # Handle the /eval endpoint (synchronous mode)
      #
      # Runs an evaluation and returns the summary.
      #
      # @param evaluators [Hash<String, Evaluator>] Available evaluators
      # @param context [RequestContext] Authenticated request context
      # @param body [Hash] Parsed request body with keys:
      #   - "name" [String] Evaluator name (required)
      #   - "data" [Array, Hash] Data specification
      #   - "parameters" [Hash] Parameter values
      #   - "scores" [Array] Additional scorer specs
      #   - "parent" [Hash] Parent object (for playground)
      #   - "experiment_name" [String] Experiment name
      #   - "project_id" [String] Project ID
      # @return [Hash] Response with :status, :headers, :body keys
      #
      def self.run_eval(evaluators:, context:, body:)
        name = body["name"]
        unless name
          return error_response("name is required", 400)
        end

        evaluator = evaluators[name]
        unless evaluator
          Braintrust::Log.error("[Handlers] Evaluator '#{name}' not found")
          return error_response("Evaluator '#{name}' not found", 404)
        end

        Braintrust::Log.info("[Handlers] Running eval: #{name}")

        begin
          # Validate and get parameters
          parameters = body["parameters"] || {}
          if evaluator.parameter_definitions.any?
            parameters = Parameters.validate(parameters, evaluator.parameter_definitions)
          end

          # Resolve data
          resolver = DataResolver.new(context.api)
          data = resolver.resolve(body["data"])

          # Build remote scorers
          extra_scorers = RemoteScorer.build_from_specs(
            context.api,
            body["scores"] || [],
            context.project_id
          )

          # Check if playground mode (has parent)
          parent = ServerHelpers.extract_parent(body)
          is_playground = ServerHelpers.playground_request?(body)
          dataset_id = DataResolver.extract_dataset_id(body["data"])

          Braintrust::Log.debug("[Handlers] Data items: #{data&.length || 0}, playground: #{is_playground}")

          # Run evaluation
          runner = EvalRunner.new(
            evaluator,
            state: context.state,
            parameters: parameters,
            no_send_logs: is_playground,
            dataset_id: dataset_id,
            parent: parent
          )

          summary = runner.run(
            data: data,
            extra_scorers: extra_scorers,
            experiment_name: body["experiment_name"],
            project_id: body["project_id"]
          )

          Braintrust::Log.info("[Handlers] Eval complete")
          success_response(summary)
        rescue ValidationError => e
          Braintrust::Log.error("[Handlers] Validation error: #{e.message}")
          error_response(e.message, 400)
        rescue => e
          Braintrust::Log.error("[Handlers] Error: #{e.message}")
          Braintrust::Log.debug(e.backtrace&.first(5)&.join("\n"))
          error_response("Internal error: #{e.message}", 500)
        end
      end

      # Handle the /eval endpoint (streaming mode)
      #
      # Runs an evaluation and yields SSE events as they're generated.
      # Use this with SSE::QueueStream for true real-time streaming.
      #
      # @param evaluators [Hash<String, Evaluator>] Available evaluators
      # @param context [RequestContext] Authenticated request context
      # @param body [Hash] Parsed request body (same as run_eval)
      # @yield [event_type, data] Called for each SSE event
      # @yieldparam event_type [String] "progress", "summary", or "done"
      # @yieldparam data [Hash, nil] Event data
      # @return [void]
      #
      # @example With queue stream
      #   queue = Queue.new
      #   stream = SSE::QueueStream.new(queue)
      #
      #   Thread.new do
      #     Handlers.run_eval_streaming(evaluators: evals, context: ctx, body: body) do |type, data|
      #       stream.event(type, data)
      #     end
      #     stream.close
      #   end
      #
      #   [200, SSE.headers_with_cors(origin), SSE::QueueBody.new(queue)]
      #
      def self.run_eval_streaming(evaluators:, context:, body:, &block)
        name = body["name"]
        unless name
          yield "error", {error: "name is required"}
          yield "done", nil
          return
        end

        evaluator = evaluators[name]
        unless evaluator
          yield "error", {error: "Evaluator '#{name}' not found"}
          yield "done", nil
          return
        end

        Braintrust::Log.info("[Handlers] Running streaming eval: #{name}")

        begin
          # Validate and get parameters
          parameters = body["parameters"] || {}
          if evaluator.parameter_definitions.any?
            parameters = Parameters.validate(parameters, evaluator.parameter_definitions)
          end

          # Resolve data
          resolver = DataResolver.new(context.api)
          data = resolver.resolve(body["data"])

          # Build remote scorers
          extra_scorers = RemoteScorer.build_from_specs(
            context.api,
            body["scores"] || [],
            context.project_id
          )

          # Check if playground mode (has parent)
          parent = ServerHelpers.extract_parent(body)
          is_playground = ServerHelpers.playground_request?(body)
          dataset_id = DataResolver.extract_dataset_id(body["data"])

          # Run evaluation with streaming callback
          runner = EvalRunner.new(
            evaluator,
            state: context.state,
            parameters: parameters,
            stream_callback: lambda { |event|
              # Only send "task" progress events (matches Python behavior)
              if event[:object_type] == "task"
                yield "progress", event
              end
            },
            no_send_logs: is_playground,
            dataset_id: dataset_id,
            parent: parent
          )

          summary = runner.run(
            data: data,
            extra_scorers: extra_scorers,
            experiment_name: body["experiment_name"],
            project_id: body["project_id"]
          )

          # Send summary (without results array)
          summary_for_sse = summary.except(:results)
          yield "summary", summary_for_sse
        rescue ValidationError => e
          Braintrust::Log.error("[Handlers] Validation error: #{e.message}")
          yield "error", {error: e.message}
        rescue => e
          Braintrust::Log.error("[Handlers] Error: #{e.message}")
          Braintrust::Log.debug(e.backtrace&.first(5)&.join("\n"))
          yield "error", {error: "Internal error: #{e.message}"}
        end

        yield "done", nil
        Braintrust::Log.info("[Handlers] Streaming eval complete")
      end

      # Build a success response hash
      #
      # @param body [Object] Response body
      # @return [Hash] Response with :status, :headers, :body
      #
      def self.success_response(body)
        {
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: body
        }
      end

      # Build an error response hash
      #
      # @param message [String] Error message
      # @param status [Integer] HTTP status code
      # @return [Hash] Response with :status, :headers, :body
      #
      def self.error_response(message, status)
        {
          status: status,
          headers: {"Content-Type" => "application/json"},
          body: {error: message}
        }
      end
    end
  end
end
