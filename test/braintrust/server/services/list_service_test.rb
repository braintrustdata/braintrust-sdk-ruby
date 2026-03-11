# frozen_string_literal: true

require "test_helper"
require "json"

# Unit tests for Services::List — runs without any framework (no appraisal needed).
module Braintrust
  module Server
    module Services
      class ListTest < Minitest::Test
        def setup
          skip_unless_server!
          @evaluators = {}
        end

        def service
          List.new(@evaluators)
        end

        def test_returns_empty_hash_when_no_evaluators
          result = service.call
          assert_equal({}, result)
        end

        def test_returns_evaluators_keyed_by_name
          @evaluators["eval-a"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
          @evaluators["eval-b"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

          result = service.call
          assert result.key?("eval-a")
          assert result.key?("eval-b")
        end

        def test_includes_scorer_names
          @evaluators["scored"] = Braintrust::Eval::Evaluator.new(
            task: ->(input) { input },
            scorers: [
              Braintrust::Eval.scorer("accuracy") { |_i, _e, _o| 1.0 },
              Braintrust::Eval.scorer("relevance") { |_i, _e, _o| 0.5 }
            ]
          )

          result = service.call
          score_names = result["scored"]["scores"].map { |s| s["name"] }
          assert_equal ["accuracy", "relevance"], score_names
        end

        def test_empty_scores_when_no_scorers
          @evaluators["no-scores"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

          result = service.call
          assert_equal [], result["no-scores"]["scores"]
        end

        def test_includes_parameters_in_static_container
          @evaluators["param-eval"] = Braintrust::Eval::Evaluator.new(
            task: ->(input) { input },
            parameters: {"temperature" => {type: "number", default: 0.7, description: "LLM temperature"}}
          )

          result = service.call
          params = result["param-eval"]["parameters"]
          assert_equal "braintrust.staticParameters", params["type"]
          assert_nil params["source"]
          assert_equal 0.7, params["schema"]["temperature"]["default"]
          assert_equal "number", params["schema"]["temperature"]["schema"]["type"]
        end

        def test_omits_parameters_when_none_defined
          @evaluators["no-params"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

          result = service.call
          refute result["no-params"].key?("parameters")
        end

        def test_result_is_json_serializable
          @evaluators["my-eval"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

          result = service.call
          json = JSON.dump(result)
          parsed = JSON.parse(json)
          assert parsed.key?("my-eval")
        end
      end
    end
  end
end
