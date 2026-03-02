# frozen_string_literal: true

require "test_helper"
require "braintrust/server"
require "json"

class Braintrust::Server::Handlers::ListTest < Minitest::Test
  def test_returns_200
    handler = Braintrust::Server::Handlers::List.new({})
    status, _, _ = handler.call({})
    assert_equal 200, status
  end

  def test_returns_json_content_type
    handler = Braintrust::Server::Handlers::List.new({})
    _, headers, _ = handler.call({})
    assert_equal "application/json", headers["content-type"]
  end

  def test_returns_empty_hash_when_no_evaluators
    handler = Braintrust::Server::Handlers::List.new({})
    _, _, body = handler.call({})
    parsed = JSON.parse(body.first)

    assert_equal({}, parsed)
  end

  def test_returns_evaluators_keyed_by_name
    evaluators = {
      "eval-a" => Braintrust::Eval::Evaluator.new(task: ->(input) { input }),
      "eval-b" => Braintrust::Eval::Evaluator.new(task: ->(input) { input })
    }
    handler = Braintrust::Server::Handlers::List.new(evaluators)

    _, _, body = handler.call({})
    parsed = JSON.parse(body.first)

    assert parsed.key?("eval-a")
    assert parsed.key?("eval-b")
  end

  def test_serializes_parameters_as_static_container
    evaluators = {
      "param-eval" => Braintrust::Eval::Evaluator.new(
        task: ->(input) { input },
        parameters: {"temp" => {type: "number", default: 0.5, description: "Temperature"}}
      )
    }
    handler = Braintrust::Server::Handlers::List.new(evaluators)

    _, _, body = handler.call({})
    parsed = JSON.parse(body.first)
    params = parsed["param-eval"]["parameters"]

    assert_equal "braintrust.staticParameters", params["type"]
    assert_nil params["source"]

    param = params["schema"]["temp"]
    assert_equal "data", param["type"]
    assert_equal({"type" => "number"}, param["schema"])
    assert_equal 0.5, param["default"]
    assert_equal "Temperature", param["description"]
  end

  def test_omits_parameters_key_when_none_defined
    evaluators = {
      "no-params" => Braintrust::Eval::Evaluator.new(task: ->(input) { input })
    }
    handler = Braintrust::Server::Handlers::List.new(evaluators)

    _, _, body = handler.call({})
    parsed = JSON.parse(body.first)

    refute parsed["no-params"].key?("parameters")
  end

  def test_includes_scorer_names
    evaluators = {
      "scored" => Braintrust::Eval::Evaluator.new(
        task: ->(input) { input },
        scorers: [
          Braintrust::Eval.scorer("accuracy") { |i, e, o| 1.0 },
          Braintrust::Eval.scorer("relevance") { |i, e, o| 0.5 }
        ]
      )
    }
    handler = Braintrust::Server::Handlers::List.new(evaluators)

    _, _, body = handler.call({})
    parsed = JSON.parse(body.first)

    score_names = parsed["scored"]["scores"].map { |s| s["name"] }
    assert_equal ["accuracy", "relevance"], score_names
  end

  def test_empty_scores_when_no_scorers
    evaluators = {
      "no-scores" => Braintrust::Eval::Evaluator.new(task: ->(input) { input })
    }
    handler = Braintrust::Server::Handlers::List.new(evaluators)

    _, _, body = handler.call({})
    parsed = JSON.parse(body.first)

    assert_equal [], parsed["no-scores"]["scores"]
  end
end
