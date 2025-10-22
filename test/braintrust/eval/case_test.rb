# frozen_string_literal: true

require "test_helper"
require "braintrust/eval/case"

class Braintrust::Eval::CaseTest < Minitest::Test
  def test_case_with_input_and_expected
    # Test basic case creation with input and expected
    test_case = Braintrust::Eval::Case.new(
      input: "apple",
      expected: "fruit"
    )

    assert_equal "apple", test_case.input
    assert_equal "fruit", test_case.expected
    assert_nil test_case.tags
    assert_nil test_case.metadata
  end

  def test_case_with_all_fields
    # Test case with all fields populated
    test_case = Braintrust::Eval::Case.new(
      input: "banana",
      expected: "fruit",
      tags: ["tropical", "sweet"],
      metadata: {color: "yellow", price: 0.5}
    )

    assert_equal "banana", test_case.input
    assert_equal "fruit", test_case.expected
    assert_equal ["tropical", "sweet"], test_case.tags
    assert_equal({color: "yellow", price: 0.5}, test_case.metadata)
  end

  def test_case_input_only
    # Test that expected, tags, and metadata are optional
    test_case = Braintrust::Eval::Case.new(input: "test")

    assert_equal "test", test_case.input
    assert_nil test_case.expected
    assert_nil test_case.tags
    assert_nil test_case.metadata
  end

  def test_case_from_hash
    # Test creating case from hash (as users will provide)
    hash = {
      input: "carrot",
      expected: "vegetable",
      tags: ["orange"],
      metadata: {category: "root"}
    }

    test_case = Braintrust::Eval::Case.new(**hash)

    assert_equal "carrot", test_case.input
    assert_equal "vegetable", test_case.expected
    assert_equal ["orange"], test_case.tags
    assert_equal({category: "root"}, test_case.metadata)
  end
end
