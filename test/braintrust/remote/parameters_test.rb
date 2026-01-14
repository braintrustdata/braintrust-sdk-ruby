# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::ParametersTest < Minitest::Test
  # ============================================
  # StringDefinition tests
  # ============================================

  def test_string_definition_validates_string
    definition = Braintrust::Remote::Parameters::StringDefinition.new(
      :test,
      default: "default"
    )

    assert_equal "hello", definition.validate("hello")
  end

  def test_string_definition_uses_default_for_nil
    definition = Braintrust::Remote::Parameters::StringDefinition.new(
      :test,
      default: "default_value"
    )

    assert_equal "default_value", definition.validate(nil)
  end

  def test_string_definition_raises_for_non_string
    definition = Braintrust::Remote::Parameters::StringDefinition.new(
      :test,
      default: ""
    )

    error = assert_raises(Braintrust::Remote::ValidationError) do
      definition.validate(123)
    end
    assert_match(/must be a string/, error.message)
  end

  def test_string_definition_to_json_schema
    definition = Braintrust::Remote::Parameters::StringDefinition.new(
      :test,
      default: "default",
      description: "A test parameter"
    )

    schema = definition.to_json_schema

    assert_equal "data", schema[:type]
    assert_equal "string", schema[:schema][:type]
    assert_equal "default", schema[:default]
    assert_equal "A test parameter", schema[:description]
  end

  # ============================================
  # NumberDefinition tests
  # ============================================

  def test_number_definition_validates_float
    definition = Braintrust::Remote::Parameters::NumberDefinition.new(
      :temperature,
      default: 0.7
    )

    assert_equal 0.9, definition.validate(0.9)
  end

  def test_number_definition_converts_to_float
    definition = Braintrust::Remote::Parameters::NumberDefinition.new(
      :test,
      default: 0.0
    )

    assert_equal 3.0, definition.validate(3)
  end

  def test_number_definition_uses_default_for_nil
    definition = Braintrust::Remote::Parameters::NumberDefinition.new(
      :test,
      default: 0.5
    )

    assert_equal 0.5, definition.validate(nil)
  end

  def test_number_definition_validates_min
    definition = Braintrust::Remote::Parameters::NumberDefinition.new(
      :test,
      default: 0.5,
      min: 0.0
    )

    error = assert_raises(Braintrust::Remote::ValidationError) do
      definition.validate(-0.1)
    end
    assert_match(/must be >= 0/, error.message)
  end

  def test_number_definition_validates_max
    definition = Braintrust::Remote::Parameters::NumberDefinition.new(
      :test,
      default: 0.5,
      max: 1.0
    )

    error = assert_raises(Braintrust::Remote::ValidationError) do
      definition.validate(1.5)
    end
    assert_match(/must be <= 1/, error.message)
  end

  def test_number_definition_to_json_schema
    definition = Braintrust::Remote::Parameters::NumberDefinition.new(
      :temperature,
      default: 0.7,
      description: "Sampling temperature"
    )

    schema = definition.to_json_schema

    assert_equal "data", schema[:type]
    assert_equal "number", schema[:schema][:type]
    assert_equal 0.7, schema[:default]
    assert_equal "Sampling temperature", schema[:description]
  end

  # ============================================
  # IntegerDefinition tests
  # ============================================

  def test_integer_definition_validates_integer
    definition = Braintrust::Remote::Parameters::IntegerDefinition.new(
      :max_tokens,
      default: 100
    )

    assert_equal 200, definition.validate(200)
  end

  def test_integer_definition_validates_float_that_equals_integer
    definition = Braintrust::Remote::Parameters::IntegerDefinition.new(
      :test,
      default: 0
    )

    assert_equal 3, definition.validate(3.0)
  end

  def test_integer_definition_rejects_non_integer_float
    definition = Braintrust::Remote::Parameters::IntegerDefinition.new(
      :test,
      default: 0
    )

    error = assert_raises(Braintrust::Remote::ValidationError) do
      definition.validate(3.7)
    end
    assert_match(/must be an integer/, error.message)
  end

  def test_integer_definition_to_json_schema
    definition = Braintrust::Remote::Parameters::IntegerDefinition.new(
      :max_tokens,
      default: 100
    )

    schema = definition.to_json_schema

    assert_equal "data", schema[:type]
    assert_equal "integer", schema[:schema][:type]
    assert_equal 100, schema[:default]
  end

  # ============================================
  # BooleanDefinition tests
  # ============================================

  def test_boolean_definition_validates_true
    definition = Braintrust::Remote::Parameters::BooleanDefinition.new(
      :enabled,
      default: false
    )

    assert_equal true, definition.validate(true)
  end

  def test_boolean_definition_validates_false
    definition = Braintrust::Remote::Parameters::BooleanDefinition.new(
      :enabled,
      default: true
    )

    assert_equal false, definition.validate(false)
  end

  def test_boolean_definition_raises_for_non_boolean
    definition = Braintrust::Remote::Parameters::BooleanDefinition.new(
      :test,
      default: false
    )

    error = assert_raises(Braintrust::Remote::ValidationError) do
      definition.validate("true")
    end
    assert_match(/must be a boolean/, error.message)
  end

  def test_boolean_definition_to_json_schema
    definition = Braintrust::Remote::Parameters::BooleanDefinition.new(
      :enabled,
      default: true,
      description: "Enable feature"
    )

    schema = definition.to_json_schema

    assert_equal "data", schema[:type]
    assert_equal "boolean", schema[:schema][:type]
    assert_equal true, schema[:default]
    assert_equal "Enable feature", schema[:description]
  end

  # ============================================
  # ArrayDefinition tests
  # ============================================

  def test_array_definition_validates_array
    definition = Braintrust::Remote::Parameters::ArrayDefinition.new(
      :tags,
      default: []
    )

    assert_equal ["a", "b"], definition.validate(["a", "b"])
  end

  def test_array_definition_uses_default_for_nil
    definition = Braintrust::Remote::Parameters::ArrayDefinition.new(
      :tags,
      default: ["default"]
    )

    assert_equal ["default"], definition.validate(nil)
  end

  def test_array_definition_raises_for_non_array
    definition = Braintrust::Remote::Parameters::ArrayDefinition.new(
      :tags,
      default: []
    )

    error = assert_raises(Braintrust::Remote::ValidationError) do
      definition.validate("not an array")
    end
    assert_match(/must be an array/, error.message)
  end

  def test_array_definition_to_json_schema
    definition = Braintrust::Remote::Parameters::ArrayDefinition.new(
      :tags,
      default: [],
      description: "List of tags"
    )

    schema = definition.to_json_schema

    assert_equal "data", schema[:type]
    assert_equal "array", schema[:schema][:type]
    assert_equal [], schema[:default]
    assert_equal "List of tags", schema[:description]
  end

  # ============================================
  # EnumDefinition tests
  # ============================================

  def test_enum_definition_validates_valid_option
    definition = Braintrust::Remote::Parameters::EnumDefinition.new(
      :model,
      values: ["gpt-4", "gpt-3.5-turbo"],
      default: "gpt-4"
    )

    assert_equal "gpt-3.5-turbo", definition.validate("gpt-3.5-turbo")
  end

  def test_enum_definition_raises_for_invalid_option
    definition = Braintrust::Remote::Parameters::EnumDefinition.new(
      :model,
      values: ["gpt-4", "gpt-3.5-turbo"],
      default: "gpt-4"
    )

    error = assert_raises(Braintrust::Remote::ValidationError) do
      definition.validate("invalid-model")
    end

    assert_match(/must be one of/, error.message)
  end

  def test_enum_definition_uses_default_for_nil
    definition = Braintrust::Remote::Parameters::EnumDefinition.new(
      :model,
      values: ["gpt-4", "gpt-3.5-turbo"],
      default: "gpt-4"
    )

    assert_equal "gpt-4", definition.validate(nil)
  end

  def test_enum_definition_to_json_schema
    definition = Braintrust::Remote::Parameters::EnumDefinition.new(
      :model,
      values: ["gpt-4", "gpt-3.5-turbo"],
      default: "gpt-4",
      description: "Model to use"
    )

    schema = definition.to_json_schema

    assert_equal "data", schema[:type]
    assert_equal "string", schema[:schema][:type]
    assert_equal ["gpt-4", "gpt-3.5-turbo"], schema[:schema][:enum]
    assert_equal "gpt-4", schema[:default]
  end

  # ============================================
  # PromptDefinition tests
  # ============================================

  def test_prompt_definition_has_default_structure
    definition = Braintrust::Remote::Parameters::PromptDefinition.new(:prompt)

    assert definition.default
    assert definition.default[:messages]
    assert definition.default[:model]
  end

  def test_prompt_definition_to_json_schema
    definition = Braintrust::Remote::Parameters::PromptDefinition.new(
      :prompt,
      description: "The prompt to use"
    )

    schema = definition.to_json_schema

    assert_equal "prompt", schema[:type]
    assert_equal "The prompt to use", schema[:description]
  end

  # ============================================
  # Builder DSL tests
  # ============================================

  def test_builder_creates_string_parameter
    builder = Braintrust::Remote::Parameters::Builder.new
    builder.string(:name, default: "test", description: "A name")

    assert builder.definitions.key?(:name)
    assert_instance_of Braintrust::Remote::Parameters::StringDefinition, builder.definitions[:name]
  end

  def test_builder_creates_number_parameter
    builder = Braintrust::Remote::Parameters::Builder.new
    builder.number(:temperature, default: 0.7)

    assert builder.definitions.key?(:temperature)
    assert_instance_of Braintrust::Remote::Parameters::NumberDefinition, builder.definitions[:temperature]
  end

  def test_builder_creates_integer_parameter
    builder = Braintrust::Remote::Parameters::Builder.new
    builder.integer(:max_tokens, default: 100)

    assert builder.definitions.key?(:max_tokens)
    assert_instance_of Braintrust::Remote::Parameters::IntegerDefinition, builder.definitions[:max_tokens]
  end

  def test_builder_creates_boolean_parameter
    builder = Braintrust::Remote::Parameters::Builder.new
    builder.boolean(:enabled, default: true)

    assert builder.definitions.key?(:enabled)
    assert_instance_of Braintrust::Remote::Parameters::BooleanDefinition, builder.definitions[:enabled]
  end

  def test_builder_creates_array_parameter
    builder = Braintrust::Remote::Parameters::Builder.new
    builder.array(:tags, default: [])

    assert builder.definitions.key?(:tags)
    assert_instance_of Braintrust::Remote::Parameters::ArrayDefinition, builder.definitions[:tags]
  end

  def test_builder_creates_enum_parameter
    builder = Braintrust::Remote::Parameters::Builder.new
    builder.enum(:model, values: ["a", "b"], default: "a")

    assert builder.definitions.key?(:model)
    assert_instance_of Braintrust::Remote::Parameters::EnumDefinition, builder.definitions[:model]
  end

  def test_builder_creates_prompt_parameter
    builder = Braintrust::Remote::Parameters::Builder.new
    builder.prompt(:prompt)

    assert builder.definitions.key?(:prompt)
    assert_instance_of Braintrust::Remote::Parameters::PromptDefinition, builder.definitions[:prompt]
  end

  # ============================================
  # Parameters.validate tests
  # ============================================

  def test_validate_returns_validated_params
    definitions = {
      name: Braintrust::Remote::Parameters::StringDefinition.new(:name, default: "default"),
      count: Braintrust::Remote::Parameters::IntegerDefinition.new(:count, default: 10)
    }

    params = {"name" => "test", "count" => 5}

    result = Braintrust::Remote::Parameters.validate(params, definitions)

    assert_equal "test", result[:name]
    assert_equal 5, result[:count]
  end

  def test_validate_applies_defaults_for_missing_params
    definitions = {
      name: Braintrust::Remote::Parameters::StringDefinition.new(:name, default: "default_name"),
      count: Braintrust::Remote::Parameters::IntegerDefinition.new(:count, default: 10)
    }

    params = {} # Empty params

    result = Braintrust::Remote::Parameters.validate(params, definitions)

    assert_equal "default_name", result[:name]
    assert_equal 10, result[:count]
  end

  def test_validate_works_with_symbol_keys
    definitions = {
      name: Braintrust::Remote::Parameters::StringDefinition.new(:name, default: "default")
    }

    params = {name: "from_symbol"}

    result = Braintrust::Remote::Parameters.validate(params, definitions)

    assert_equal "from_symbol", result[:name]
  end
end
