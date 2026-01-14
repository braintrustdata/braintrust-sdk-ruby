# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::RemoteScorerTest < Minitest::Test
  # ============================================
  # Constructor tests
  # ============================================

  def test_initializes_with_required_fields
    api = mock_api

    scorer = Braintrust::Remote::RemoteScorer.new(
      name: "factuality",
      api: api,
      function_id: "func-123"
    )

    assert_equal "factuality", scorer.name
  end

  def test_initializes_with_project_id
    api = mock_api

    scorer = Braintrust::Remote::RemoteScorer.new(
      name: "factuality",
      api: api,
      function_id: "func-123",
      project_id: "proj-456"
    )

    assert_equal "factuality", scorer.name
  end

  # ============================================
  # call tests
  # ============================================

  def test_call_invokes_api_function
    api = mock_api
    invocations = []

    # Track invocations
    api.define_singleton_method(:functions) do
      funcs = Object.new
      funcs.define_singleton_method(:invoke_scorer) do |**kwargs|
        invocations << kwargs
        {"score" => 0.95, "metadata" => {}}
      end
      funcs
    end

    scorer = Braintrust::Remote::RemoteScorer.new(
      name: "factuality",
      api: api,
      function_id: "func-123",
      project_id: "proj-456"
    )

    result = scorer.call(
      input: "What is 2+2?",
      output: "4",
      expected: "4",
      metadata: {source: "test"}
    )

    assert_equal 1, invocations.length
    assert_equal "func-123", invocations[0][:function_id]
    assert_equal "proj-456", invocations[0][:project_id]
    assert_equal "What is 2+2?", invocations[0][:input][:input]
    assert_equal "4", invocations[0][:input][:output]
    assert_equal 0.95, result["score"]
  end

  # ============================================
  # build_from_specs tests
  # ============================================

  def test_build_from_specs_returns_empty_array_for_nil
    api = mock_api

    scorers = Braintrust::Remote::RemoteScorer.build_from_specs(api, nil)

    assert_equal [], scorers
  end

  def test_build_from_specs_returns_empty_array_for_empty_array
    api = mock_api

    scorers = Braintrust::Remote::RemoteScorer.build_from_specs(api, [])

    assert_equal [], scorers
  end

  def test_build_from_specs_creates_scorers_from_specs
    api = mock_api

    specs = [
      {"name" => "factuality", "function_id" => "func-1"},
      {"name" => "relevance", "function_id" => "func-2"}
    ]

    scorers = Braintrust::Remote::RemoteScorer.build_from_specs(api, specs, "proj-123")

    assert_equal 2, scorers.length
    assert_equal "factuality", scorers[0].name
    assert_equal "relevance", scorers[1].name
    assert_instance_of Braintrust::Remote::RemoteScorer, scorers[0]
    assert_instance_of Braintrust::Remote::RemoteScorer, scorers[1]
  end

  private

  def mock_api
    Object.new
  end
end
