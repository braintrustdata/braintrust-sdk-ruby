# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::EvaluatorTest < Minitest::Test
  def setup
    # Clear any existing evaluators before each test
    Braintrust::Remote.clear_evaluators!
  end

  def teardown
    Braintrust::Remote.clear_evaluators!
  end

  # ============================================
  # Constructor tests
  # ============================================

  def test_initializes_with_name
    evaluator = Braintrust::Remote::Evaluator.new("Test Evaluator")

    assert_equal "Test Evaluator", evaluator.name
  end

  def test_initializes_with_project_name
    evaluator = Braintrust::Remote::Evaluator.new(
      "Test",
      project_name: "my-project"
    )

    assert_equal "my-project", evaluator.project_name
  end

  def test_initializes_with_experiment_name
    evaluator = Braintrust::Remote::Evaluator.new(
      "Test",
      experiment_name: "my-experiment"
    )

    assert_equal "my-experiment", evaluator.experiment_name
  end

  def test_initializes_with_description
    evaluator = Braintrust::Remote::Evaluator.new(
      "Test",
      description: "A test evaluator"
    )

    assert_equal "A test evaluator", evaluator.description
  end

  # ============================================
  # DSL: data method tests
  # ============================================

  def test_data_with_inline_array
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      data [
        {input: "a", expected: "A"},
        {input: "b", expected: "B"}
      ]
    end

    assert_equal 2, evaluator.resolve_data.length
  end

  def test_data_with_block
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      data do
        [
          {input: "generated", expected: "GENERATED"}
        ]
      end
    end

    result = evaluator.resolve_data
    assert_equal 1, result.length
    assert_equal "generated", result[0].input
  end

  def test_data_returns_eval_case_objects
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      data [{input: "test", expected: "TEST"}]
    end

    result = evaluator.resolve_data
    assert_instance_of Braintrust::Remote::EvalCase, result[0]
  end

  # ============================================
  # DSL: task method tests
  # ============================================

  def test_task_stores_block
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      task { |input| input.upcase }
    end

    assert evaluator.task_block
  end

  def test_run_task_executes_task_block
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      task { |input| input.upcase }
    end

    hooks = Braintrust::Remote::EvalHooks.new
    result = evaluator.run_task("hello", hooks)

    assert_equal "HELLO", result
  end

  def test_run_task_passes_hooks_to_block
    received_hooks = nil

    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      task { |input, hooks|
        received_hooks = hooks
        input.upcase
      }
    end

    hooks = Braintrust::Remote::EvalHooks.new(parameters: {model: "gpt-4"})
    evaluator.run_task("test", hooks)

    assert_equal hooks, received_hooks
    assert_equal "gpt-4", received_hooks.parameters[:model]
  end

  # ============================================
  # DSL: scores method tests
  # ============================================

  def test_scores_with_array_of_lambdas
    scorer1 = ->(input:, output:, expected:, **) { 1.0 }
    scorer2 = ->(input:, output:, expected:, **) { 0.5 }

    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      scores [scorer1, scorer2]
    end

    assert_equal 2, evaluator.scorers.length
  end

  def test_scores_with_named_scorer_objects
    scorer = Object.new
    def scorer.name
      "accuracy"
    end

    def scorer.call(input:, output:, expected:, **)
      (output == expected) ? 1.0 : 0.0
    end

    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      scores [scorer]
    end

    assert_equal 1, evaluator.scorers.length
  end

  # ============================================
  # DSL: parameters method tests
  # ============================================

  def test_parameters_with_hash
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      parameters(
        model: Braintrust::Remote::Parameters::StringDefinition.new(
          :model,
          default: "gpt-4"
        )
      )
    end

    assert evaluator.parameter_definitions.key?(:model)
  end

  def test_parameters_with_block_dsl
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      parameters do
        string :model, default: "gpt-4", description: "Model to use"
        number :temperature, default: 0.7
        integer :max_tokens, default: 100
        boolean :stream, default: false
      end
    end

    definitions = evaluator.parameter_definitions

    assert definitions.key?(:model)
    assert definitions.key?(:temperature)
    assert definitions.key?(:max_tokens)
    assert definitions.key?(:stream)

    assert_instance_of Braintrust::Remote::Parameters::StringDefinition, definitions[:model]
    assert_instance_of Braintrust::Remote::Parameters::NumberDefinition, definitions[:temperature]
  end

  def test_parameters_with_enum
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      parameters do
        enum :model, values: ["gpt-4", "gpt-3.5-turbo"], default: "gpt-4"
      end
    end

    assert_instance_of(
      Braintrust::Remote::Parameters::EnumDefinition,
      evaluator.parameter_definitions[:model]
    )
  end

  def test_parameters_with_prompt
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      parameters do
        prompt :system_prompt, description: "System prompt to use"
      end
    end

    assert_instance_of(
      Braintrust::Remote::Parameters::PromptDefinition,
      evaluator.parameter_definitions[:system_prompt]
    )
  end

  # ============================================
  # parameters_to_json_schema tests
  # ============================================

  def test_parameters_to_json_schema_returns_definitions
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      parameters do
        string :name, default: "test"
        number :value, default: 0.5
      end
    end

    schema = evaluator.parameters_to_json_schema

    assert schema.key?(:name)
    assert schema.key?(:value)
    assert_equal "data", schema[:name][:type]
    assert_equal "data", schema[:value][:type]
  end

  def test_parameters_to_json_schema_empty_when_no_parameters
    evaluator = Braintrust::Remote::Evaluator.new("Test")

    schema = evaluator.parameters_to_json_schema

    assert_equal({}, schema)
  end

  # ============================================
  # scorer_info tests
  # ============================================

  def test_scorer_info_returns_array_of_scorer_metadata
    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      scores [
        ->(input:, output:, expected:, **) { 1.0 }
      ]
    end

    info = evaluator.scorer_info

    assert_instance_of Array, info
    assert_equal 1, info.length
    assert info[0].key?(:name)
  end

  def test_scorer_info_uses_scorer_name_if_available
    scorer = Object.new
    def scorer.name
      "accuracy"
    end

    def scorer.call(**)
      1.0
    end

    evaluator = Braintrust::Remote::Evaluator.new("Test") do
      scores [scorer]
    end

    info = evaluator.scorer_info

    assert_equal "accuracy", info[0][:name]
  end

  # ============================================
  # Registration tests
  # ============================================

  def test_evaluator_method_registers_evaluator
    Braintrust::Remote.evaluator("Registered Eval") do
      task { |input| input }
    end

    assert Braintrust::Remote.evaluators.key?("Registered Eval")
  end

  def test_eval_alias_works_same_as_evaluator
    Braintrust::Remote.eval("Aliased Eval") do
      task { |input| input }
    end

    assert Braintrust::Remote.evaluators.key?("Aliased Eval")
  end

  def test_clear_evaluators_removes_all
    Braintrust::Remote.evaluator("Test1") { task { |i| i } }
    Braintrust::Remote.evaluator("Test2") { task { |i| i } }

    assert_equal 2, Braintrust::Remote.evaluators.length

    Braintrust::Remote.clear_evaluators!

    assert_equal 0, Braintrust::Remote.evaluators.length
  end

  # ============================================
  # Full evaluator definition tests
  # ============================================

  def test_complete_evaluator_definition
    evaluator = Braintrust::Remote.evaluator(
      "Complete Evaluator",
      project_name: "test-project",
      description: "A complete test evaluator"
    ) do
      data [
        {input: "hello", expected: "HELLO"},
        {input: "world", expected: "WORLD"}
      ]

      task { |input, hooks|
        model = hooks.parameters[:model] || "default"
        "#{input.upcase} (#{model})"
      }

      scores [
        ->(input:, output:, expected:, **) {
          output.start_with?(expected) ? 1.0 : 0.0
        }
      ]

      parameters do
        string :model, default: "gpt-4", description: "Model to use"
        number :temperature, default: 0.7
      end
    end

    assert_equal "Complete Evaluator", evaluator.name
    assert_equal "test-project", evaluator.project_name
    assert_equal 2, evaluator.resolve_data.length
    assert_equal 1, evaluator.scorers.length
    assert_equal 2, evaluator.parameter_definitions.length
  end
end
