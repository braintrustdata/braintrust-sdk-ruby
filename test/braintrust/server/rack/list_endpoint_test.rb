# frozen_string_literal: true

require "test_helper"
require "braintrust/server"
require "rack/test"
require "json"

# Integration tests for GET/POST /list through the full Rack middleware stack.
class Braintrust::Server::Rack::ListEndpointTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @evaluators = {}
  end

  def app
    Braintrust::Server::Rack.app(evaluators: @evaluators, auth: :none)
  end

  def test_returns_empty_when_no_evaluators
    post "/list", nil, {"CONTENT_TYPE" => "application/json"}

    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal({}, body)
  end

  def test_returns_evaluators_keyed_by_name
    @evaluators["food-classifier"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
    @evaluators["text-summarizer"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    post "/list", nil, {"CONTENT_TYPE" => "application/json"}

    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert body.key?("food-classifier")
    assert body.key?("text-summarizer")
  end

  def test_includes_parameters_in_static_container
    @evaluators["param-eval"] = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input },
      parameters: {"temperature" => {type: "number", default: 0.7, description: "LLM temperature"}}
    )

    post "/list", nil, {"CONTENT_TYPE" => "application/json"}

    body = JSON.parse(last_response.body)
    params = body["param-eval"]["parameters"]
    assert_equal "braintrust.staticParameters", params["type"]
    assert_equal 0.7, params["schema"]["temperature"]["default"]
  end

  def test_includes_scorer_names
    @evaluators["scored-eval"] = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input },
      scorers: [
        Braintrust::Eval.scorer("exact_match") { |i, e, o| (o == e) ? 1.0 : 0.0 },
        Braintrust::Eval.scorer("length_check") { |i, e, o| 1.0 }
      ]
    )

    post "/list", nil, {"CONTENT_TYPE" => "application/json"}

    body = JSON.parse(last_response.body)
    score_names = body["scored-eval"]["scores"].map { |s| s["name"] }
    assert_equal ["exact_match", "length_check"], score_names
  end

  def test_omits_parameters_when_none_defined
    @evaluators["no-params"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    post "/list", nil, {"CONTENT_TYPE" => "application/json"}

    body = JSON.parse(last_response.body)
    refute body["no-params"].key?("parameters")
  end

  def test_accepts_get
    get "/list"
    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_kind_of Hash, body
  end
end
