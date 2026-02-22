# frozen_string_literal: true

require "test_helper"
require "braintrust/server"
require "rack/test"
require "json"

# Integration tests for POST /list through the full Rack middleware stack.
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
    assert_equal [], body["evaluators"]
  end

  def test_returns_evaluator_names
    @evaluators["food-classifier"] = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
    @evaluators["text-summarizer"] = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input },
      parameters: {"max_length" => {type: "number", default: 100}}
    )

    post "/list", nil, {"CONTENT_TYPE" => "application/json"}

    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    names = body["evaluators"].map { |e| e["name"] }
    assert_includes names, "food-classifier"
    assert_includes names, "text-summarizer"
  end

  def test_includes_parameters
    @evaluators["param-eval"] = Braintrust::Eval::Evaluator.new(
      task: ->(input) { input },
      parameters: {"temperature" => {type: "number", default: 0.7, description: "LLM temperature"}}
    )

    post "/list", nil, {"CONTENT_TYPE" => "application/json"}

    body = JSON.parse(last_response.body)
    eval_entry = body["evaluators"].find { |e| e["name"] == "param-eval" }
    assert_equal 0.7, eval_entry["parameters"]["temperature"]["default"]
  end

  def test_rejects_get
    get "/list"
    assert_equal 405, last_response.status
  end
end
