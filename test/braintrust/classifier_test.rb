# frozen_string_literal: true

require "test_helper"
require "braintrust/classifier"

class Braintrust::ClassifierTest < Minitest::Test
  # ============================================
  # Classifier.new with block (inline classifiers)
  # ============================================

  def test_classifier_with_kwargs_block
    classifier = Braintrust::Classifier.new("category") do |output:, **|
      {name: "category", id: "greeting", label: "Greeting"}
    end

    assert_equal "category", classifier.name
    result = classifier.call(input: "hello", expected: nil, output: "hello")
    assert_equal [{name: "category", id: "greeting", label: "Greeting"}], result
  end

  def test_classifier_with_subset_kwargs_filters_extra_keys
    classifier = Braintrust::Classifier.new("category") do |output:|
      {name: "category", id: "word"}
    end

    result = classifier.call(input: "x", expected: nil, output: "hello", metadata: {}, tags: ["t"])
    assert_equal [{name: "category", id: "word"}], result
  end

  def test_classifier_returns_nil_produces_empty_array
    classifier = Braintrust::Classifier.new("maybe") { |**| nil }
    assert_equal [], classifier.call(output: "hello")
  end

  def test_classifier_returns_array_of_classifications
    classifier = Braintrust::Classifier.new("sentiment") do |**|
      [
        {name: "sentiment", id: "positive", label: "Positive"},
        {name: "sentiment", id: "enthusiastic", label: "Enthusiastic"}
      ]
    end

    result = classifier.call(output: "great!")
    assert_equal 2, result.length
    assert_equal({name: "sentiment", id: "positive", label: "Positive"}, result[0])
    assert_equal({name: "sentiment", id: "enthusiastic", label: "Enthusiastic"}, result[1])
  end

  def test_classifier_with_metadata
    classifier = Braintrust::Classifier.new("category") do |**|
      {name: "category", id: "greeting", label: "Greeting", metadata: {source: "unit-test"}}
    end

    result = classifier.call(output: "hello")
    assert_equal [{name: "category", id: "greeting", label: "Greeting", metadata: {source: "unit-test"}}], result
  end

  # ============================================
  # Name defaulting
  # ============================================

  def test_name_defaults_to_classifier_function_name_when_missing
    classifier = Braintrust::Classifier.new("my_classifier") { |**|
      {id: "foo"} # no :name key
    }

    result = classifier.call(output: "x")
    assert_equal "my_classifier", result[0][:name]
  end

  def test_name_defaults_to_classifier_function_name_when_empty_string
    classifier = Braintrust::Classifier.new("my_classifier") { |**|
      {name: "", id: "foo"}
    }

    result = classifier.call(output: "x")
    assert_equal "my_classifier", result[0][:name]
  end

  def test_name_defaults_to_classifier_function_name_when_not_a_string
    classifier = Braintrust::Classifier.new("my_classifier") { |**|
      {name: 42, id: "foo"}
    }

    result = classifier.call(output: "x")
    assert_equal "my_classifier", result[0][:name]
  end

  def test_explicit_name_in_result_takes_precedence
    classifier = Braintrust::Classifier.new("my_classifier") { |**|
      {name: "override_name", id: "foo"}
    }

    result = classifier.call(output: "x")
    assert_equal "override_name", result[0][:name]
  end

  # ============================================
  # Validation
  # ============================================

  def test_classifier_non_empty_object_validation_nil_item
    classifier = Braintrust::Classifier.new("bad") { |**| [nil] }

    error = assert_raises(ArgumentError) do
      classifier.call(output: "x")
    end
    assert_match(/each classification must be a non-empty object/, error.message)
    assert_match(/nil/, error.message)
  end

  def test_classifier_non_empty_object_validation_empty_hash
    classifier = Braintrust::Classifier.new("bad") { |**| {} }

    error = assert_raises(ArgumentError) do
      classifier.call(output: "x")
    end
    assert_match(/each classification must be a non-empty object/, error.message)
  end

  def test_classifier_non_empty_object_validation_string_item
    classifier = Braintrust::Classifier.new("bad") { |**| ["not-a-hash"] }

    error = assert_raises(ArgumentError) do
      classifier.call(output: "x")
    end
    assert_match(/each classification must be a non-empty object/, error.message)
  end

  def test_classifier_non_empty_object_validation_non_hash_scalar
    classifier = Braintrust::Classifier.new("bad") { |**| 42 }

    error = assert_raises(ArgumentError) do
      classifier.call(output: "x")
    end
    assert_match(/each classification must be a non-empty object/, error.message)
  end

  def test_classifier_positional_params_raises
    error = assert_raises(ArgumentError) do
      Braintrust::Classifier.new("bad") { |a, b| a }
    end

    assert_match(/classifier block must use keyword args/i, error.message)
  end

  # ============================================
  # Name detection
  # ============================================

  def test_classifier_name_defaults_to_classifier_for_base_class
    classifier = Braintrust::Classifier.new { |**| {id: "x"} }
    assert_equal "classifier", classifier.name
  end

  def test_classifier_explicit_name_takes_precedence
    classifier = Braintrust::Classifier.new("my_name") { |**| {id: "x"} }
    assert_equal "my_name", classifier.name
  end

  # ============================================
  # Subclass pattern
  # ============================================

  def test_subclass_with_call_override
    klass = Class.new do
      include Braintrust::Classifier

      def call(output:)
        {name: "category", id: output.empty? ? "empty" : "nonempty"}
      end
    end

    classifier = klass.new
    assert_kind_of Braintrust::Classifier, classifier

    result = classifier.call(input: "x", expected: nil, output: "hello")
    assert_equal [{name: "category", id: "nonempty"}], result

    result2 = classifier.call(input: "x", expected: nil, output: "")
    assert_equal [{name: "category", id: "empty"}], result2
  end

  def test_subclass_with_name_override
    klass = Class.new do
      include Braintrust::Classifier

      def name
        "custom_classifier"
      end

      def call(**)
        {id: "foo"}
      end
    end

    classifier = klass.new
    assert_equal "custom_classifier", classifier.name
  end

  def test_subclass_name_derived_from_class_name
    klass = Class.new do
      include Braintrust::Classifier

      def call(**)
        {id: "foo"}
      end
    end

    Braintrust.stub_const(:FuzzyMatchTestClassifier, klass) do
      classifier = klass.new
      assert_equal "fuzzy_match_test_classifier", classifier.name
    end
  end

  def test_subclass_without_call_raises_on_call
    klass = Class.new do
      include Braintrust::Classifier
    end
    classifier = klass.new

    assert_raises(NoMethodError) do
      classifier.call(output: "x")
    end
  end
end
