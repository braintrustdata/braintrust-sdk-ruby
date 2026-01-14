# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::HandlersTest < Minitest::Test
  def setup
    Braintrust::Remote.clear_evaluators!
  end

  def teardown
    Braintrust::Remote.clear_evaluators!
  end

  # ============================================
  # prepare_request tests
  # ============================================

  def test_prepare_request_unauthorized_without_context
    result = Braintrust::Remote::Handlers.prepare_request(
      context: nil,
      body_json: '{"name": "test"}'
    )

    refute result[:ok]
    assert_equal 401, result[:status]
    assert_equal "Unauthorized", result[:error]
  end

  def test_prepare_request_unauthorized_when_not_authorized
    context = mock_context(authorized: false)

    result = Braintrust::Remote::Handlers.prepare_request(
      context: context,
      body_json: '{"name": "test"}'
    )

    refute result[:ok]
    assert_equal 401, result[:status]
  end

  def test_prepare_request_invalid_json
    context = mock_context(authorized: true)

    result = Braintrust::Remote::Handlers.prepare_request(
      context: context,
      body_json: "not valid json"
    )

    refute result[:ok]
    assert_equal 400, result[:status]
    assert_equal "Invalid JSON", result[:error]
  end

  def test_prepare_request_success_non_streaming
    context = mock_context(authorized: true)

    result = Braintrust::Remote::Handlers.prepare_request(
      context: context,
      body_json: '{"name": "test", "stream": false}'
    )

    assert result[:ok]
    refute result[:stream]
    assert_equal "test", result[:body]["name"]
  end

  def test_prepare_request_success_streaming
    context = mock_context(authorized: true)

    result = Braintrust::Remote::Handlers.prepare_request(
      context: context,
      body_json: '{"name": "test", "stream": true}'
    )

    assert result[:ok]
    assert result[:stream]
  end

  # ============================================
  # list_evaluators tests
  # ============================================

  def test_list_evaluators_empty
    result = Braintrust::Remote::Handlers.list_evaluators({})

    assert_equal({}, result)
  end

  def test_list_evaluators_returns_formatted_list
    Braintrust::Remote.evaluator("Eval1") do
      parameters { string :model, default: "gpt-4" }
      scores [Braintrust::Remote::InlineScorer.new("accuracy") { 1.0 }]
    end

    Braintrust::Remote.evaluator("Eval2") do
      task { |input| input.upcase }
    end

    result = Braintrust::Remote::Handlers.list_evaluators(Braintrust::Remote.evaluators)

    assert result.key?("Eval1")
    assert result.key?("Eval2")
    assert result["Eval1"][:parameters].key?(:model)
    assert_equal "accuracy", result["Eval1"][:scores][0][:name]
  end

  # ============================================
  # run_eval tests
  # ============================================

  def test_run_eval_missing_name
    context = mock_context(authorized: true)

    result = Braintrust::Remote::Handlers.run_eval(
      evaluators: {},
      context: context,
      body: {}
    )

    assert_equal 400, result[:status]
    assert_equal "name is required", result[:body][:error]
  end

  def test_run_eval_evaluator_not_found
    context = mock_context(authorized: true)

    result = Braintrust::Remote::Handlers.run_eval(
      evaluators: {},
      context: context,
      body: {"name" => "NonExistent"}
    )

    assert_equal 404, result[:status]
    assert_match(/not found/, result[:body][:error])
  end

  def test_run_eval_success
    Braintrust::Remote.evaluator("SimpleEval") do
      task { |input| input.upcase }
      scores [
        ->(input:, output:, expected:, **) { (output == expected) ? 1.0 : 0.0 }
      ]
    end

    context = mock_context(authorized: true, with_api: true)

    result = Braintrust::Remote::Handlers.run_eval(
      evaluators: Braintrust::Remote.evaluators,
      context: context,
      body: {
        "name" => "SimpleEval",
        "data" => [
          {"input" => "hello", "expected" => "HELLO"}
        ],
        "parent" => {"object_type" => "playground_logs"} # Playground mode to skip experiment creation
      }
    )

    assert_equal 200, result[:status]
    assert result[:body].key?(:experimentName)
    assert result[:body].key?(:scores)
  end

  # ============================================
  # success_response tests
  # ============================================

  def test_success_response
    result = Braintrust::Remote::Handlers.success_response({data: "test"})

    assert_equal 200, result[:status]
    assert_equal "application/json", result[:headers]["Content-Type"]
    assert_equal({data: "test"}, result[:body])
  end

  # ============================================
  # error_response tests
  # ============================================

  def test_error_response
    result = Braintrust::Remote::Handlers.error_response("Something went wrong", 500)

    assert_equal 500, result[:status]
    assert_equal "application/json", result[:headers]["Content-Type"]
    assert_equal({error: "Something went wrong"}, result[:body])
  end

  private

  def mock_context(authorized:, with_api: false)
    ctx = Object.new

    ctx.define_singleton_method(:authorized?) { authorized }

    if with_api
      # Create a mock state that won't try to login or make HTTP calls
      state = Object.new
      state.define_singleton_method(:logged_in) { true }
      state.define_singleton_method(:api_url) { nil } # Return nil to prevent HTTP calls in flush_spans_to_parent
      state.define_singleton_method(:api_key) { "test-key" }
      state.define_singleton_method(:org_name) { "test-org" }
      state.define_singleton_method(:login) { true }

      # Mock API with datasets
      api = Object.new
      datasets = Object.new
      datasets.define_singleton_method(:fetch_rows) { |id:| [] }
      api.define_singleton_method(:datasets) { datasets }

      ctx.define_singleton_method(:state) { state }
      ctx.define_singleton_method(:api) { api }
      ctx.define_singleton_method(:project_id) { nil }
    end

    ctx
  end
end
