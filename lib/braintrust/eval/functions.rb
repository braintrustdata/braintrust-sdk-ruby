# frozen_string_literal: true

require_relative "../api"
require_relative "scorer"
require "opentelemetry/sdk"
require "json"

module Braintrust
  module Eval
    # Functions provides remote function execution capabilities
    # Allows calling prompts hosted on Braintrust servers as tasks or scorers
    module Functions
      class << self
        # Create a task callable that invokes a remote function
        # @param project [String] Project name
        # @param slug [String] Function slug
        # @param state [State, nil] Braintrust state (defaults to global)
        # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider
        # @return [Proc] Callable that accepts input and returns output
        def task(project:, slug:, state: nil, tracer_provider: nil)
          state ||= Braintrust.current_state
          raise Error, "No state available" unless state

          # Resolve function ID from project + slug
          api = API.new(state: state)
          function_metadata = resolve_function(api, project, slug)
          function_id = function_metadata["id"]
          function_name = function_metadata["name"] || slug

          # Get tracer for creating spans
          tracer_provider ||= OpenTelemetry.tracer_provider
          tracer = tracer_provider.tracer("braintrust.functions")

          # Return a lambda that invokes the remote function with tracing
          lambda do |input|
            # Create a span for the function invocation
            tracer.in_span("function: #{slug}") do |span|
              span.set_attribute("braintrust.span_attributes", JSON.dump({type: "function"}))
              span.set_attribute("braintrust.input_json", JSON.dump(input))
              span.set_attribute("braintrust.function.name", function_name)
              span.set_attribute("braintrust.function.id", function_id)
              span.set_attribute("braintrust.function.slug", slug)

              begin
                # Invoke the function via API
                output = api.functions.invoke(id: function_id, input: input)
                span.set_attribute("braintrust.output_json", JSON.dump(output))
                output
              rescue => e
                # Record exception and set error status
                span.record_exception(e)
                span.status = OpenTelemetry::Trace::Status.error(e.message)
                raise
              end
            end
          end
        end

        # Create a scorer that invokes a remote function by ID
        # @param id [String] Function UUID
        # @param version [String, nil] Optional version to pin to
        # @param state [State, nil] Braintrust state (defaults to global)
        # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider
        # @return [Scorer] Scorer object that invokes remote function
        def scorer_by_id(id:, state: nil, version: nil, tracer_provider: nil)
          state ||= Braintrust.current_state
          api = API.new(state: state)
          api.login

          function_metadata = api.functions.get(id: id, version: version)
          function_id = function_metadata["id"]
          function_name = function_metadata["name"] || id

          tracer_provider ||= OpenTelemetry.tracer_provider
          tracer = tracer_provider.tracer("braintrust.functions")

          build_scorer(function_id: function_id, function_name: function_name, api: api, tracer: tracer)
        end

        # Create a scorer that invokes a remote function
        # @param project [String] Project name
        # @param slug [String] Function slug
        # @param state [State, nil] Braintrust state (defaults to global)
        # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider
        # @return [Scorer] Scorer object that invokes remote function
        def scorer(project:, slug:, state: nil, tracer_provider: nil)
          state ||= Braintrust.current_state
          raise Error, "No state available" unless state

          # Resolve function ID from project + slug
          api = API.new(state: state)
          function_metadata = resolve_function(api, project, slug)
          function_id = function_metadata["id"]
          function_name = function_metadata["name"] || slug

          # Get tracer for creating spans
          tracer_provider ||= OpenTelemetry.tracer_provider
          tracer = tracer_provider.tracer("braintrust.functions")

          build_scorer(function_id: function_id, function_name: function_name, api: api, tracer: tracer)
        end

        private

        # Build a Scorer that invokes a remote function
        # Shared implementation used by both scorer and scorer_by_id
        # @param function_id [String] Function UUID
        # @param function_name [String] Function display name
        # @param api [API] Braintrust API client
        # @param tracer [OpenTelemetry::Trace::Tracer] Tracer instance
        # @return [Scorer]
        def build_scorer(function_id:, function_name:, api:, tracer:)
          Scorer.new(function_name) do |input, expected, output, metadata|
            tracer.in_span("function: #{function_name}") do |span|
              scorer_input = {
                input: input,
                expected: expected,
                output: output,
                metadata: metadata
              }

              span.set_attribute("braintrust.span_attributes", JSON.dump({type: "function"}))
              span.set_attribute("braintrust.input_json", JSON.dump(scorer_input))
              span.set_attribute("braintrust.function.name", function_name)
              span.set_attribute("braintrust.function.id", function_id)

              begin
                result = api.functions.invoke(id: function_id, input: scorer_input)

                score = case result
                when Hash
                  if result.key?("score")
                    result["score"].to_f
                  else
                    raise Error, "Hash result must contain 'score' key"
                  end
                when String
                  result.to_f
                else
                  raise Error, "Unsupported result type: #{result.class}"
                end

                span.set_attribute("braintrust.output_json", JSON.dump(score))
                score
              rescue => e
                span.record_exception(e)
                span.status = OpenTelemetry::Trace::Status.error(e.message)
                raise
              end
            end
          end
        end

        # Resolve function ID from project name and slug
        # @param api [API] API client
        # @param project [String] Project name
        # @param slug [String] Function slug
        # @return [Hash] Function metadata
        def resolve_function(api, project, slug)
          result = api.functions.list(project_name: project, slug: slug)
          functions = result["objects"]

          if functions.nil? || functions.empty?
            raise Error, "Function '#{slug}' not found in project '#{project}'"
          end

          functions.first
        end
      end
    end
  end
end
