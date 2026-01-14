# frozen_string_literal: true

module Braintrust
  module Remote
    # DSL for defining evaluators that can be served remotely
    class Evaluator
      attr_reader :name, :description
      attr_accessor :data_source, :task_block, :scorers, :parameter_definitions

      def initialize(name, project_name: nil, experiment_name: nil, description: nil, &block)
        @name = name
        @project_name = project_name || name
        @experiment_name = experiment_name
        @description = description
        @data_source = []
        @task_block = nil
        @scorers = []
        @parameter_definitions = {}

        instance_eval(&block) if block_given?
      end

      # DSL Methods

      # Set the project name
      # @param name [String] Project name
      def project_name(name = nil)
        if name
          @project_name = name
        else
          @project_name
        end
      end

      # Set the experiment name
      # @param name [String] Experiment name
      def experiment_name(name = nil)
        if name
          @experiment_name = name
        else
          @experiment_name
        end
      end

      # Set inline data
      # @param items [Array<Hash>] Array of eval cases with :input, :expected, :metadata
      def data(items = nil, &block)
        if block_given?
          @data_source = block
        elsif items
          @data_source = items
        end
      end

      # Set the task function
      # @yield [input, hooks] Block that takes input and optional hooks, returns output
      def task(&block)
        @task_block = block
      end

      # Add scorers
      # @param scorer_list [Array<Proc, Object>] Scorers (procs or objects with #call or #score)
      def scores(scorer_list)
        @scorers = scorer_list
      end

      # Define a single scorer inline
      # @param name [String] Scorer name
      # @yield Block that returns a score
      def scorer(name, &block)
        @scorers << InlineScorer.new(name, &block)
      end

      # Define parameters
      # @param params [Hash] Parameter definitions (optional if using block)
      # @yield Block for DSL-style parameter definition
      def parameters(params = nil, &block)
        if block_given?
          # DSL-style: parameters { string :name, default: "value" }
          builder = Parameters::Builder.new
          builder.instance_eval(&block)
          @parameter_definitions = builder.definitions
        elsif params
          # Hash-style: parameters({ name: Parameters.string(...) })
          @parameter_definitions = params.transform_values do |definition|
            case definition
            when Parameters::Definition
              definition
            when Hash
              Parameters.from_hash(definition)
            else
              raise ArgumentError, "Invalid parameter definition: #{definition.class}"
            end
          end
        end
      end

      # Execution Methods

      # Resolve the data source to an array of EvalCases
      # @return [Array<EvalCase>]
      def resolve_data
        case @data_source
        when Proc
          result = @data_source.call
          normalize_data(result)
        when Array
          normalize_data(@data_source)
        else
          []
        end
      end

      # Run the task on an input
      # @param input [Object] The input to the task
      # @param hooks [EvalHooks] Hooks for metadata and progress
      # @return [Object] The task output
      def run_task(input, hooks)
        raise Braintrust::Error, "No task defined for evaluator '#{@name}'" unless @task_block

        if @task_block.arity == 2
          @task_block.call(input, hooks)
        else
          @task_block.call(input)
        end
      end

      # Serialization Methods

      # Convert parameters to JSON schema format for /list endpoint
      # @return [Hash] Parameters in JSON schema format
      def parameters_to_json_schema
        return {} if @parameter_definitions.empty?

        @parameter_definitions.transform_values do |definition|
          definition.to_json_schema
        end
      end

      # Get scorer info for /list endpoint
      # @return [Array<Hash>] Array of scorer info with :name
      def scorer_info
        @scorers.each_with_index.map do |scorer, idx|
          {name: ScorerUtils.extract_name(scorer, idx)}
        end
      end

      private

      def normalize_data(items)
        items.map do |item|
          case item
          when EvalCase
            item
          when Hash
            EvalCase.from_hash(item)
          else
            raise ArgumentError, "Invalid data item: #{item.class}"
          end
        end
      end
    end

    # Inline scorer defined with DSL
    class InlineScorer
      attr_reader :name

      def initialize(name, &block)
        @name = name
        @block = block
      end

      def call(input:, output:, expected:, metadata:)
        @block.call(input: input, output: output, expected: expected, metadata: metadata)
      end
    end
  end
end
