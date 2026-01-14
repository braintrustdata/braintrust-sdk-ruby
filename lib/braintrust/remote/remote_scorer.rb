# frozen_string_literal: true

module Braintrust
  module Remote
    # A scorer that invokes a Braintrust function remotely
    #
    # Remote scorers are defined in Braintrust and can be used from the playground.
    # They're invoked via the Braintrust API and return scores just like local scorers.
    #
    # @example Create a remote scorer
    #   scorer = RemoteScorer.new(
    #     name: "factuality",
    #     api: braintrust_api,
    #     function_id: "func-abc123",
    #     project_id: "proj-xyz789"
    #   )
    #
    # @example Use in evaluation
    #   result = scorer.call(
    #     input: "What is 2+2?",
    #     output: "4",
    #     expected: "4",
    #     metadata: {}
    #   )
    #   # => { "score" => 1.0, "metadata" => { ... } }
    #
    class RemoteScorer
      # @return [String] The scorer name
      attr_reader :name

      # Create a new remote scorer
      #
      # @param name [String] Display name for the scorer
      # @param api [Braintrust::API] Braintrust API client
      # @param function_id [String] The Braintrust function ID to invoke
      # @param project_id [String, nil] Optional project ID for context
      #
      def initialize(name:, api:, function_id:, project_id: nil)
        @name = name
        @api = api
        @function_id = function_id
        @project_id = project_id
      end

      # Invoke the remote scorer
      #
      # @param input [Object] The input that was evaluated
      # @param output [Object] The output from the task
      # @param expected [Object, nil] The expected output (ground truth)
      # @param metadata [Hash] Additional metadata
      # @return [Hash] The score result from the remote function
      #
      def call(input:, output:, expected:, metadata: {})
        @api.functions.invoke_scorer(
          function_id: @function_id,
          input: {
            input: input,
            output: output,
            expected: expected,
            metadata: metadata
          },
          project_id: @project_id
        )
      end

      # Build remote scorers from score specifications
      #
      # @param api [Braintrust::API] Braintrust API client
      # @param score_specs [Array<Hash>] Array of score specifications from request
      # @param project_id [String, nil] Optional project ID
      # @return [Array<RemoteScorer>] Array of remote scorer instances
      #
      # @example
      #   specs = [{ "name" => "factuality", "function_id" => "func-123" }]
      #   scorers = RemoteScorer.build_from_specs(api, specs, project_id)
      #
      def self.build_from_specs(api, score_specs, project_id = nil)
        return [] unless score_specs

        score_specs.map do |spec|
          new(
            name: spec["name"],
            api: api,
            function_id: spec["function_id"],
            project_id: project_id
          )
        end
      end
    end
  end
end
