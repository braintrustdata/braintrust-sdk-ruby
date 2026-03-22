# frozen_string_literal: true

require_relative "cases"

module Braintrust
  module Eval
    # Holds all normalized, ready-to-execute eval components.
    # Use Context.build to construct from raw user inputs.
    class Context
      attr_reader :task, :scorers, :cases, :experiment_id, :experiment_name,
        :project_id, :project_name, :state, :tracer_provider,
        :on_progress, :parent_span_attr, :generation

      def initialize(task:, scorers:, cases:, experiment_id: nil, experiment_name: nil,
        project_id: nil, project_name: nil, state: nil, tracer_provider: nil,
        on_progress: nil, parent_span_attr: nil, generation: nil)
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
      end

      # Build a Context from raw user inputs.
      # Delegates to Factory for normalization.
      def self.build(task:, scorers:, cases:, experiment_id: nil, experiment_name: nil,
        project_id: nil, project_name: nil, state: nil, tracer_provider: nil,
        on_progress: nil, parent: nil)
        Factory.new(
          state: state, tracer_provider: tracer_provider,
          project_id: project_id, project_name: project_name
        ).build(
          task: task, scorers: scorers, cases: cases,
          experiment_id: experiment_id, experiment_name: experiment_name,
          on_progress: on_progress, parent: parent
        )
      end

      # Encapsulates normalization of raw user inputs into typed wrappers.
      class Factory
        def initialize(state: nil, tracer_provider: nil, project_id: nil, project_name: nil)
          @state = state
          @tracer_provider = tracer_provider
          @project_id = project_id
          @project_name = project_name
        end

        def build(task:, scorers:, cases:, experiment_id: nil, experiment_name: nil,
          on_progress: nil, parent: nil)
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
            generation: parent&.dig(:generation)
          )
        end

        private

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

        def resolve_parent_span_attr(parent)
          return nil unless parent
          "#{parent[:object_type]}:#{parent[:object_id]}"
        end

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
