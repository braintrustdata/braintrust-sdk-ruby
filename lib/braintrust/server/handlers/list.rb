# frozen_string_literal: true

require "json"

module Braintrust
  module Server
    module Handlers
      # GET/POST /list — returns all evaluators keyed by name.
      #
      # Response format (Braintrust dev server protocol):
      #   {
      #     "evaluator-name": {
      #       "parameters": {                          # optional
      #         "type": "braintrust.staticParameters",
      #         "schema": {
      #           "param_name": { "type": "data", "schema": {...}, "default": ..., "description": ... }
      #         },
      #         "source": null
      #       },
      #       "scores": [{ "name": "scorer_name" }, ...]
      #     }
      #   }
      class List
        def initialize(evaluators)
          @evaluators = evaluators
        end

        def call(_env)
          result = {}
          @evaluators.each do |name, evaluator|
            scores = (evaluator.scorers || []).each_with_index.map do |scorer, i|
              scorer_name = scorer.respond_to?(:name) ? scorer.name : "score_#{i}"
              {"name" => scorer_name}
            end
            entry = {"scores" => scores}
            params = serialize_parameters(evaluator.parameters)
            entry["parameters"] = params if params
            result[name] = entry
          end

          [200, {"content-type" => "application/json"},
            [JSON.dump(result)]]
        end

        private

        # Convert user-defined parameters to the dev server protocol format.
        # Wraps in a staticParameters container with "data" typed entries.
        def serialize_parameters(parameters)
          return nil unless parameters && !parameters.empty?

          schema = {}
          parameters.each do |name, spec|
            spec = spec.transform_keys(&:to_s) if spec.is_a?(Hash)
            if spec.is_a?(Hash)
              schema[name.to_s] = {
                "type" => "data",
                "schema" => {"type" => spec["type"] || "string"},
                "default" => spec["default"],
                "description" => spec["description"]
              }
            end
          end

          {
            "type" => "braintrust.staticParameters",
            "schema" => schema,
            "source" => nil
          }
        end
      end
    end
  end
end
