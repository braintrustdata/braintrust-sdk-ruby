# frozen_string_literal: true

require_relative "cases"

module Braintrust
  module Eval
    # Holds all normalized, ready-to-execute eval components.
    # Use Context.build to construct from raw user inputs.
    class Context
      attr_reader :task, :scorers, :cases, :experiment_id, :experiment_name,
        :project_id, :project_name, :state, :tracer_provider,
        :on_progress, :parent_span_attr, :generation, :parameters

      # @param task [Task] Normalized task wrapper
      # @param scorers [Array<Scorer>] Normalized scorer wrappers
      # @param cases [Cases] Normalized eval cases
      # @param experiment_id [String, nil] Experiment ID for logging and trace linkage
      # @param experiment_name [String, nil] Experiment name, included in span attributes
      # @param project_id [String, nil] Project ID
      # @param project_name [String, nil] Project name
      # @param state [Braintrust::State, nil] Authenticated API state; nil for local-only evals
      # @param tracer_provider [#tracer, nil] OpenTelemetry tracer provider
      # @param on_progress [Proc, nil] Callback invoked after each case completes, receiving a progress Hash
      # @param parent_span_attr [String, nil] Formatted parent span identifier ("type:id"), linking spans to a parent context
      # @param generation [Integer, nil] Generation number from the parent span context, used to link spans in a trace hierarchy
      # @param parameters [Hash, nil] Runtime parameters passed to task and scorers as a `parameters:` keyword argument
      def initialize(task:, scorers:, cases:, experiment_id: nil, experiment_name: nil,
        project_id: nil, project_name: nil, state: nil, tracer_provider: nil,
        on_progress: nil, parent_span_attr: nil, generation: nil, parameters: nil)
        @task = task
        @scorers = scorers
        @cases = cases
        @experiment_id = experiment_id
        @experiment_name = experiment_name
        @project_id = project_id
        @project_name = project_name
        @state = state
        @tracer_provider = tracer_provider
        @on_progress = on_progress
        @parent_span_attr = parent_span_attr
        @generation = generation
        @parameters = parameters
      end

      # Build a Context from raw user inputs.
      # Delegates to Factory for normalization.
      # @param task [Task, Proc, #call] Task to evaluate; wrapped into a {Task} if needed
      # @param scorers [Array<Scorer, Proc, String, Scorer::ID, #call>] Scorers; each is normalized into a {Scorer}
      # @param cases [Cases, Array, Enumerable] Eval cases; wrapped into {Cases} if needed
      # @param experiment_id [String, nil] Experiment ID for logging
      # @param experiment_name [String, nil] Experiment name, included in span attributes
      # @param project_id [String, nil] Project ID
      # @param project_name [String, nil] Project name; required when resolving scorer slugs
      # @param state [Braintrust::State, nil] Authenticated API state; nil for local-only evals
      # @param tracer_provider [#tracer, nil] OpenTelemetry tracer provider; defaults to global provider
      # @param on_progress [Proc, nil] Callback invoked after each case completes, receiving a progress Hash
      # @param parent [Hash, nil] Parent span info with keys :object_type, :object_id, and optionally :generation
      # @param parameters [Hash, nil] Runtime parameters passed to task and scorers as a `parameters:` keyword argument
      # @return [Context]
      def self.build(task:, scorers:, cases:, experiment_id: nil, experiment_name: nil,
        project_id: nil, project_name: nil, state: nil, tracer_provider: nil,
        on_progress: nil, parent: nil, parameters: nil)
        Factory.new(
          state: state, tracer_provider: tracer_provider,
          project_id: project_id, project_name: project_name
        ).build(
          task: task, scorers: scorers, cases: cases,
          experiment_id: experiment_id, experiment_name: experiment_name,
          on_progress: on_progress, parent: parent, parameters: parameters
        )
      end

      # Encapsulates normalization of raw user inputs into typed wrappers.
      class Factory
        # @param state [Braintrust::State, nil] Authenticated API state; passed through to scorer resolution
        # @param tracer_provider [#tracer, nil] OpenTelemetry tracer provider; passed through to remote scorers
        # @param project_id [String, nil] Project ID; passed through to the built Context
        # @param project_name [String, nil] Project name; required when resolving scorer slugs
        def initialize(state: nil, tracer_provider: nil, project_id: nil, project_name: nil)
          @state = state
          @tracer_provider = tracer_provider
          @project_id = project_id
          @project_name = project_name
        end

        # Normalize raw inputs and construct a {Context}.
        # @param task [Task, Proc, #call] Raw task
        # @param scorers [Array] Raw scorers
        # @param cases [Cases, Array, Enumerable] Raw eval cases
        # @param experiment_id [String, nil]
        # @param experiment_name [String, nil]
        # @param on_progress [Proc, nil]
        # @param parent [Hash, nil] Parent span info with keys :object_type, :object_id, and optionally :generation
        # @return [Context]
        def build(task:, scorers:, cases:, experiment_id: nil, experiment_name: nil,
          on_progress: nil, parent: nil, parameters: nil)
          Context.new(
            task: normalize_task(task),
            scorers: normalize_scorers(scorers),
            cases: normalize_cases(cases),
            experiment_id: experiment_id,
            experiment_name: experiment_name,
            project_id: @project_id,
            project_name: @project_name,
            state: @state,
            tracer_provider: @tracer_provider || OpenTelemetry.tracer_provider,
            on_progress: on_progress,
            parent_span_attr: resolve_parent_span_attr(parent),
            generation: parent&.dig(:generation),
            parameters: parameters
          )
        end

        private

        # @param raw [Cases, Array, Enumerable, #each]
        # @return [Cases]
        # @raise [ArgumentError] if raw is not enumerable
        def normalize_cases(raw)
          case raw
          when Cases
            raw
          when Array, Enumerable
            Cases.new(raw)
          else
            if raw.respond_to?(:each)
              Cases.new(raw)
            else
              raise ArgumentError, "cases must be Array or Enumerable"
            end
          end
        end

        # @param parent [Hash, nil]
        # @return [String, nil] Formatted as "type:id", e.g. "experiment_id:abc-123"
        def resolve_parent_span_attr(parent)
          return nil unless parent
          "#{parent[:object_type]}:#{parent[:object_id]}"
        end

        # @param raw [Task, Proc, #call]
        # @return [Task]
        def normalize_task(raw)
          case raw
          when Task
            raw
          when Proc
            # Pass Proc/Lambda directly to preserve keyword arg info.
            # Legacy positional lambdas (arity 1) are auto-wrapped by Task#wrap_block.
            Task.new(&raw)
          else
            # Callable class: wrap via method(:call) to preserve keyword arg info
            name = raw.respond_to?(:name) ? raw.name : nil
            Task.new(name, &raw.method(:call))
          end
        end

        # @param raw [Array<Scorer, Proc, String, Scorer::ID, #call>]
        # @return [Array<Scorer>]
        # @raise [ArgumentError] if a String slug is given without a project name
        def normalize_scorers(raw)
          raw.map do |scorer|
            case scorer
            when String
              raise ArgumentError, "project is required to resolve scorer slug '#{scorer}'" unless @project_name
              Braintrust::Functions.scorer(
                project: @project_name,
                slug: scorer,
                state: @state,
                tracer_provider: @tracer_provider
              )
            when Braintrust::Scorer::ID
              Braintrust::Functions.scorer(
                id: scorer.function_id,
                version: scorer.version,
                state: @state,
                tracer_provider: @tracer_provider
              )
            when Braintrust::Scorer
              scorer
            when Proc
              # Pass Proc/Lambda directly to preserve keyword arg info
              # (method(:call) loses parameter metadata)
              Braintrust::Scorer.new(&scorer)
            else
              name = scorer.respond_to?(:name) ? scorer.name : nil
              Braintrust::Scorer.new(name, &scorer.method(:call))
            end
          end
        end
      end
    end
  end
end
