# frozen_string_literal: true

require "json"

module Braintrust
  module Server
    module Handlers
      # POST /list — returns all evaluators with their parameters.
      class List
        def initialize(evaluators)
          @evaluators = evaluators
        end

        def call(_env)
          evaluators = @evaluators.map do |name, evaluator|
            entry = {"name" => name}
            entry["parameters"] = evaluator.parameters unless evaluator.parameters.empty?
            entry
          end

          [200, {"content-type" => "application/json"},
            [JSON.dump({"evaluators" => evaluators})]]
        end
      end
    end
  end
end
