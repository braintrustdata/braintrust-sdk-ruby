# frozen_string_literal: true

require "json"

module Braintrust
  module Server
    module Services
      # Framework-agnostic service for listing evaluators.
      # Returns a plain Hash (not a Rack triplet) suitable for JSON.dump.
      class List
        def initialize(evaluators)
          @evaluators = evaluators
        end

        def call
          result = {}
          current_evaluators.each do |name, evaluator|
            scores = (evaluator.scorers || []).each_with_index.map do |scorer, i|
              scorer_name = scorer.respond_to?(:name) ? scorer.name : "score_#{i}"
              {"name" => scorer_name}
            end
            entry = {"scores" => scores}
            classifiers = (evaluator.classifiers || []).each_with_index.map do |classifier, i|
              classifier_name = classifier.respond_to?(:name) ? classifier.name : "classifier_#{i}"
              {"name" => classifier_name}
            end
            entry["classifiers"] = classifiers unless classifiers.empty?
            params = serialize_parameters(evaluator.parameters)
            entry["parameters"] = params if params
            result[name] = entry
          end
          result
        end

        private

        def current_evaluators
          return @evaluators.call if @evaluators.respond_to?(:call)
          @evaluators
        end

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
