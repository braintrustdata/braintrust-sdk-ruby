# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::EvalCaseTest < Minitest::Test
  # ============================================
  # Constructor tests
  # ============================================

  def test_initializes_with_input_only
    eval_case = Braintrust::Remote::EvalCase.new(input: "test input")

    assert_equal "test input", eval_case.input
    assert_nil eval_case.expected
    assert_equal({}, eval_case.metadata)  # Defaults to empty hash
    assert_nil eval_case.id
    assert_nil eval_case.created
  end

  def test_initializes_with_all_attributes
    eval_case = Braintrust::Remote::EvalCase.new(
      input: "test input",
      expected: "expected output",
      metadata: {key: "value"},
      id: "case-123",
      created: "2024-01-01T00:00:00Z"
    )

    assert_equal "test input", eval_case.input
    assert_equal "expected output", eval_case.expected
    assert_equal({key: "value"}, eval_case.metadata)
    assert_equal "case-123", eval_case.id
    assert_equal "2024-01-01T00:00:00Z", eval_case.created
  end

  # ============================================
  # from_hash tests
  # ============================================

  def test_from_hash_with_string_keys
    hash = {
      "input" => "test input",
      "expected" => "expected output",
      "metadata" => {"key" => "value"}
    }

    eval_case = Braintrust::Remote::EvalCase.from_hash(hash)

    assert_equal "test input", eval_case.input
    assert_equal "expected output", eval_case.expected
    assert_equal({"key" => "value"}, eval_case.metadata)
  end

  def test_from_hash_with_symbol_keys
    hash = {
      input: "test input",
      expected: "expected output",
      metadata: {key: "value"}
    }

    eval_case = Braintrust::Remote::EvalCase.from_hash(hash)

    assert_equal "test input", eval_case.input
    assert_equal "expected output", eval_case.expected
    assert_equal({key: "value"}, eval_case.metadata)
  end

  def test_from_hash_extracts_id_and_created
    hash = {
      "input" => "test",
      "id" => "row-abc",
      "created" => "2024-06-15T12:00:00Z"
    }

    eval_case = Braintrust::Remote::EvalCase.from_hash(hash)

    assert_equal "row-abc", eval_case.id
    assert_equal "2024-06-15T12:00:00Z", eval_case.created
  end

  def test_from_hash_with_xact_id
    # _xact_id is preserved in metadata for origin tracking
    hash = {
      "input" => "test input",
      "expected" => "expected output",
      "_xact_id" => "xact-123"
    }

    eval_case = Braintrust::Remote::EvalCase.from_hash(hash)

    assert_equal "xact-123", eval_case.metadata["_xact_id"]
  end

  def test_from_hash_with_tags
    hash = {
      "input" => "test",
      "expected" => "TEST",
      "tags" => ["tag1", "tag2"]
    }

    eval_case = Braintrust::Remote::EvalCase.from_hash(hash)

    assert_equal ["tag1", "tag2"], eval_case.tags
  end

  # ============================================
  # to_h tests
  # ============================================

  def test_to_h_returns_hash_representation
    eval_case = Braintrust::Remote::EvalCase.new(
      input: "test input",
      expected: "expected output",
      metadata: {key: "value"}
    )

    result = eval_case.to_h

    assert_equal "test input", result[:input]
    assert_equal "expected output", result[:expected]
    assert_equal({key: "value"}, result[:metadata])
  end

  def test_to_h_excludes_nil_values
    eval_case = Braintrust::Remote::EvalCase.new(input: "test")

    result = eval_case.to_h

    # Note: metadata defaults to {} and is included, but expected/id/created are nil and excluded
    assert_equal "test", result[:input]
    assert_equal({}, result[:metadata])
    refute result.key?(:expected)
    refute result.key?(:id)
    refute result.key?(:created)
  end

  # ============================================
  # Edge cases
  # ============================================

  def test_input_can_be_complex_object
    complex_input = {
      "messages" => [
        {"role" => "user", "content" => "Hello"}
      ],
      "context" => {"session_id" => "123"}
    }

    eval_case = Braintrust::Remote::EvalCase.new(input: complex_input)

    assert_equal complex_input, eval_case.input
  end

  def test_expected_can_be_complex_object
    complex_expected = {
      "response" => "Hello!",
      "metadata" => {"confidence" => 0.95}
    }

    eval_case = Braintrust::Remote::EvalCase.new(
      input: "test",
      expected: complex_expected
    )

    assert_equal complex_expected, eval_case.expected
  end
end
