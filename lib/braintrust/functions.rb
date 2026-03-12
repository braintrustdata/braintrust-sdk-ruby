# frozen_string_literal: true

require_relative "api"
require_relative "scorer"
require_relative "task"
require "opentelemetry/sdk"
require "json"

module Braintrust
  # Functions provides remote function execution capabilities.
  # Allows calling prompts hosted on Braintrust servers as tasks or scorers.
  module Functions
    class << self
      # Create a Task that invokes a remote function
      # @param project [String] Project name
      # @param slug [String] Function slug
      # @param state [State, nil] Braintrust state (defaults to global)
      # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider
      # @return [Task] Task object that invokes remote function
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

        Task.new(function_name) do |input:|
          tracer.in_span("function: #{slug}") do |span|
            span.set_attribute("braintrust.span_attributes", JSON.dump({type: "function"}))
            span.set_attribute("braintrust.input_json", JSON.dump(input))
            span.set_attribute("braintrust.function.name", function_name)
            span.set_attribute("braintrust.function.id", function_id)
            span.set_attribute("braintrust.function.slug", slug)

            begin
              output = api.functions.invoke(id: function_id, input: input)
              span.set_attribute("braintrust.output_json", JSON.dump(output))
              output
            rescue => e
              span.record_exception(e)
              span.status = OpenTelemetry::Trace::Status.error(e.message)
              raise
            end
          end
        end
      end

      # Create a scorer that invokes a remote function.
      # Resolve by project + slug, or by function UUID (id).
      # @param project [String, nil] Project name (used with slug)
      # @param slug [String, nil] Function slug (used with project)
      # @param id [String, nil] Function UUID (alternative to project + slug)
      # @param version [String, nil] Optional version to pin to (used with id)
      # @param state [State, nil] Braintrust state (defaults to global)
      # @param tracer_provider [TracerProvider, nil] OpenTelemetry tracer provider
      # @return [Scorer] Scorer object that invokes remote function
      def scorer(project: nil, slug: nil, id: nil, version: nil, state: nil, tracer_provider: nil)
        has_id = !id.nil?
        has_project_slug = !project.nil? && !slug.nil?

        unless has_id || has_project_slug
          raise ArgumentError, "scorer requires either id: or both project: and slug:"
        end

        state ||= Braintrust.current_state
        raise Error, "No state available" unless state

        api = API.new(state: state)

        function_metadata = if id
          api.login
          api.functions.get(id: id, version: version)
        else
          resolve_function(api, project, slug)
        end

        function_id = function_metadata["id"]
        function_name = function_metadata["name"] || id || slug

        tracer_provider ||= OpenTelemetry.tracer_provider
        tracer = tracer_provider.tracer("braintrust.functions")

        build_scorer(function_id: function_id, function_name: function_name, api: api, tracer: tracer)
      end

      private

      # Build a Scorer that invokes a remote function
      # @param function_id [String] Function UUID
      # @param function_name [String] Function display name
      # @param api [API] Braintrust API client
      # @param tracer [OpenTelemetry::Trace::Tracer] Tracer instance
      # @return [Scorer]
      def build_scorer(function_id:, function_name:, api:, tracer:)
        Scorer.new(function_name) do |input:, expected:, output:, metadata:|
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
              when Numeric
                result.to_f
              when true
                1.0
              when false
                0.0
              when Hash
                if result.key?("score")
                  result["score"].to_f
                else
                  raise Error, "Hash result must contain 'score' key"
                end
              when String
                result.to_f
              when nil
                nil
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
