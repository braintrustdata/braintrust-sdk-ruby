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
          @service = Services::List.new(evaluators)
        end

        def call(_env)
          result = @service.call
          [200, {"content-type" => "application/json"}, [JSON.dump(result)]]
        end
      end
    end
  end
end
