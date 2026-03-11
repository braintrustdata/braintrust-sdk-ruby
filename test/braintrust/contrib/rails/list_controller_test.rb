# frozen_string_literal: true

require "test_helper"
require "json"

module Braintrust
  module Contrib
    module Rails
      class ListControllerTest < Minitest::Test
        include ::Rack::Test::Methods if defined?(::Rack::Test::Methods)

        def setup
          skip_unless_rails_server!
          @evaluators = {}
          reset_engine!(evaluators: @evaluators, auth: :none)
        end

        def app
          rails_engine_app
        end

        def test_get_list_returns_200
          get "/list"
          assert_equal 200, last_response.status
        end

        def test_post_list_returns_200
          post "/list"
          assert_equal 200, last_response.status
        end

        def test_returns_empty_hash_when_no_evaluators
          get "/list"
          body = JSON.parse(last_response.body)
          assert_equal({}, body)
        end

        def test_returns_evaluators_keyed_by_name
          @evaluators["food-classifier"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
          @evaluators["text-summarizer"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
          reset_engine!(evaluators: @evaluators, auth: :none)

          get "/list"
          body = JSON.parse(last_response.body)
          assert body.key?("food-classifier")
          assert body.key?("text-summarizer")
        end

        def test_includes_scorer_names
          @evaluators["scored-eval"] = Braintrust::Eval::Evaluator.new(
            task: ->(input) { input },
            scorers: [
              Braintrust::Eval.scorer("exact_match") { |_i, e, o| (o == e) ? 1.0 : 0.0 },
              Braintrust::Eval.scorer("length_check") { |_i, _e, _o| 1.0 }
            ]
          )
          reset_engine!(evaluators: @evaluators, auth: :none)

          get "/list"
          body = JSON.parse(last_response.body)
          score_names = body["scored-eval"]["scores"].map { |s| s["name"] }
          assert_equal ["exact_match", "length_check"], score_names
        end

        def test_includes_parameters_in_static_container
          @evaluators["param-eval"] = Braintrust::Eval::Evaluator.new(
            task: ->(input) { input },
            parameters: {"temperature" => {type: "number", default: 0.7, description: "LLM temperature"}}
          )
          reset_engine!(evaluators: @evaluators, auth: :none)

          get "/list"
          body = JSON.parse(last_response.body)
          params = body["param-eval"]["parameters"]
          assert_equal "braintrust.staticParameters", params["type"]
          assert_equal 0.7, params["schema"]["temperature"]["default"]
        end

        def test_omits_parameters_when_none_defined
          @evaluators["no-params"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
          reset_engine!(evaluators: @evaluators, auth: :none)

          get "/list"
          body = JSON.parse(last_response.body)
          refute body["no-params"].key?("parameters")
        end

        def test_returns_401_when_auth_fails
          # Use clerk_token auth — no auth header means failure
          reset_engine!(evaluators: @evaluators, auth: :clerk_token)

          # WebMock blocks real HTTP, so clerk token validation will fail
          get "/list"
          assert_equal 401, last_response.status
        end
      end
    end
  end
end
