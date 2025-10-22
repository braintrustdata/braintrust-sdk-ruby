# frozen_string_literal: true

require "test_helper"
require "braintrust/eval/case"
require "braintrust/eval/cases"

class Braintrust::Eval::CasesTest < Minitest::Test
  def test_cases_from_array_of_hashes
    # Test creating Cases from array of hashes
    cases_input = [
      {input: "apple", expected: "fruit"},
      {input: "carrot", expected: "vegetable"}
    ]

    cases = Braintrust::Eval::Cases.new(cases_input)

    result = []
    cases.each do |test_case|
      result << test_case
    end

    assert_equal 2, result.length
    assert_instance_of Braintrust::Eval::Case, result[0]
    assert_equal "apple", result[0].input
    assert_equal "fruit", result[0].expected
  end

  def test_cases_from_array_of_case_objects
    # Test that Cases accepts already-built Case objects
    cases_input = [
      Braintrust::Eval::Case.new(input: "apple", expected: "fruit"),
      Braintrust::Eval::Case.new(input: "carrot", expected: "vegetable")
    ]

    cases = Braintrust::Eval::Cases.new(cases_input)

    result = []
    cases.each do |test_case|
      result << test_case
    end

    assert_equal 2, result.length
    assert_equal "apple", result[0].input
  end

  def test_cases_from_enumerator
    # Test creating Cases from lazy enumerator
    enumerator = Enumerator.new do |yielder|
      yielder << {input: "apple", expected: "fruit"}
      yielder << {input: "carrot", expected: "vegetable"}
    end

    cases = Braintrust::Eval::Cases.new(enumerator)

    result = []
    cases.each do |test_case|
      result << test_case
    end

    assert_equal 2, result.length
    assert_equal "apple", result[0].input
  end

  def test_cases_with_all_fields
    # Test that Cases preserves tags and metadata
    cases_input = [
      {
        input: "apple",
        expected: "fruit",
        tags: ["sweet"],
        metadata: {color: "red"}
      }
    ]

    cases = Braintrust::Eval::Cases.new(cases_input)

    result = []
    cases.each do |test_case|
      result << test_case
    end

    assert_equal ["sweet"], result[0].tags
    assert_equal({color: "red"}, result[0].metadata)
  end

  def test_cases_lazy_evaluation
    # Test that enumerator is evaluated lazily
    evaluated = []

    enumerator = Enumerator.new do |yielder|
      evaluated << 1
      yielder << {input: "first", expected: "a"}
      evaluated << 2
      yielder << {input: "second", expected: "b"}
    end

    cases = Braintrust::Eval::Cases.new(enumerator)

    # Creating Cases should not trigger evaluation
    assert_equal [], evaluated

    # Iterating should trigger evaluation
    cases.each { |_| break }  # Break after first

    # Should have evaluated first item only
    assert_equal [1], evaluated
  end

  def test_cases_count
    # Test that Cases provides count method
    cases_input = [
      {input: "apple", expected: "fruit"},
      {input: "carrot", expected: "vegetable"}
    ]

    cases = Braintrust::Eval::Cases.new(cases_input)

    # For arrays, count should work
    assert_equal 2, cases.count
  end
end
