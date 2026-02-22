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

  def test_returns_empty_evaluators_when_none
    handler = Braintrust::Server::Handlers::List.new({})
    _, _, body = handler.call({})
    parsed = JSON.parse(body.first)

    assert_equal [], parsed["evaluators"]
  end

  def test_returns_evaluator_names
    evaluators = {
      "eval-a" => Braintrust::Eval::Evaluator.new(task: ->(input) { input }),
      "eval-b" => Braintrust::Eval::Evaluator.new(task: ->(input) { input })
    }
    handler = Braintrust::Server::Handlers::List.new(evaluators)

    _, _, body = handler.call({})
    parsed = JSON.parse(body.first)
    names = parsed["evaluators"].map { |e| e["name"] }

    assert_includes names, "eval-a"
    assert_includes names, "eval-b"
  end

  def test_includes_parameters_when_present
    evaluators = {
      "param-eval" => Braintrust::Eval::Evaluator.new(
        task: ->(input) { input },
        parameters: {"temp" => {type: "number", default: 0.5}}
      )
    }
    handler = Braintrust::Server::Handlers::List.new(evaluators)

    _, _, body = handler.call({})
    parsed = JSON.parse(body.first)
    eval_entry = parsed["evaluators"].find { |e| e["name"] == "param-eval" }

    assert_equal 0.5, eval_entry["parameters"]["temp"]["default"]
  end

  def test_omits_parameters_key_when_empty
    evaluators = {
      "no-params" => Braintrust::Eval::Evaluator.new(task: ->(input) { input })
    }
    handler = Braintrust::Server::Handlers::List.new(evaluators)

    _, _, body = handler.call({})
    parsed = JSON.parse(body.first)
    eval_entry = parsed["evaluators"].find { |e| e["name"] == "no-params" }

    refute eval_entry.key?("parameters")
  end
end
