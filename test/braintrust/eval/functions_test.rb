# frozen_string_literal: true

require "test_helper"
require "braintrust/eval"
require "braintrust/eval/functions"

class Braintrust::Eval::FunctionsTest < Minitest::Test
  def setup
    @project_name = "ruby-sdk-test"
  end

  def get_test_state_and_api
    state = get_integration_test_state
    api = Braintrust::API.new(state: state)
    [state, api]
  end

  def test_functions_task_returns_callable
    VCR.use_cassette("eval_functions/task_callable") do
      state, api = get_test_state_and_api
      # This test verifies that Functions.task returns a callable object
      # The callable should accept an input and invoke the remote function
      function_slug = "test-ruby-sdk-task-callable"

      # Create a simple remote function
      api.functions.create(
        project_name: @project_name,
        slug: function_slug,
        function_data: {type: "prompt"},
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "Say hello to {{input}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini",
            params: {temperature: 0}
          }
        }
      )

      # Get a task wrapper
      task = Braintrust::Eval::Functions.task(
        project: @project_name,
        slug: function_slug,
        state: state
      )

      # Should be callable
      assert_respond_to task, :call
    end
  end

  def test_functions_task_invokes_remote
    VCR.use_cassette("eval_functions/task_invoke") do
      state, api = get_test_state_and_api
      # This test verifies that calling the task actually invokes the remote function
      function_slug = "test-ruby-sdk-task-invoke"

      # Create a simple remote function
      api.functions.create(
        project_name: @project_name,
        slug: function_slug,
        function_data: {type: "prompt"},
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "Say hello to {{input}}"}
            ]
          },
          options: {
            model: "gpt-4o-mini",
            params: {temperature: 0}
          }
        }
      )

      # Get task and invoke it
      task = Braintrust::Eval::Functions.task(
        project: @project_name,
        slug: function_slug,
        state: state
      )

      result = task.call("world")

      # Should return output from remote function
      assert_instance_of String, result
      assert result.length > 0
    end
  end

  def test_functions_scorer_returns_scorer
    VCR.use_cassette("eval_functions/scorer") do
      state, api = get_test_state_and_api
      # This test verifies that Functions.scorer returns a Scorer object
      function_slug = "test-ruby-sdk-scorer"

      # Create a simple remote scorer
      api.functions.create(
        project_name: @project_name,
        slug: function_slug,
        function_data: {type: "prompt"},
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "system", content: "You are a scorer. Return a score between 0 and 1."},
              {role: "user", content: "Score this: {{output}}. Return just a number."}
            ]
          },
          options: {
            model: "gpt-4o-mini",
            params: {temperature: 0}
          }
        }
      )

      # Get a scorer wrapper
      scorer = Braintrust::Eval::Functions.scorer(
        project: @project_name,
        slug: function_slug,
        state: state
      )

      # Should be a Scorer instance
      assert_instance_of Braintrust::Eval::Scorer, scorer
      assert_equal function_slug, scorer.name
    end
  end

  def test_use_remote_task_in_eval_run
    VCR.use_cassette("eval_functions/eval_run") do
      state, api = get_test_state_and_api
      # This test verifies that remote tasks can be used in Eval.run
      # This is the main use case: calling server-side prompts in evals
      function_slug = "test-ruby-sdk-eval-task"

      # Create a remote function that uppercases input
      api.functions.create(
        project_name: @project_name,
        slug: function_slug,
        function_data: {type: "prompt"},
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "user", content: "Uppercase this: {{input}}. Return ONLY the uppercase version, nothing else."}
            ]
          },
          options: {
            model: "gpt-4o-mini",
            params: {temperature: 0}
          }
        }
      )

      # Get remote task
      task = Braintrust::Eval::Functions.task(
        project: @project_name,
        slug: function_slug,
        state: state
      )

      # Use in Eval.run with a simple exact match scorer
      result = Braintrust::Eval.run(
        project: @project_name,
        experiment: "test-ruby-sdk-remote-task-eval",
        cases: [
          {input: "hello", expected: "HELLO"},
          {input: "world", expected: "WORLD"}
        ],
        task: task,
        scorers: [
          Braintrust::Eval.scorer("contains_uppercase") do |input, expected, output|
            # Check if output contains expected (LLM might add extra text)
            output.to_s.include?(expected) ? 1.0 : 0.0
          end
        ],
        api: api,
        quiet: true
      )

      # Should complete successfully
      assert_instance_of Braintrust::Eval::Result, result
      assert result.duration > 0
    end
  end

  def test_use_remote_scorer_in_eval_run
    VCR.use_cassette("eval_functions/remote_scorer") do
      state, api = get_test_state_and_api
      # This test verifies that remote scorers can be used in Eval.run
      # This tests the "online scorer" functionality
      function_slug = "test-ruby-sdk-eval-scorer"

      # Create a remote scorer function with LLM classifier
      api.functions.create(
        project_name: @project_name,
        slug: function_slug,
        function_data: {type: "prompt"},
        prompt_data: {
          prompt: {
            type: "chat",
            messages: [
              {role: "system", content: "You are a scorer. Evaluate if the output matches the expected value."},
              {role: "user", content: "Does '{{output}}' match '{{expected}}'? Answer 'correct' or 'incorrect'."}
            ]
          },
          options: {
            model: "gpt-4o-mini",
            params: {temperature: 0},
            parser: {
              type: "llm_classifier",
              use_cot: true,
              choice_scores: {
                "correct" => 1.0,
                "incorrect" => 0.0
              }
            }
          }
        }
      )

      # Get remote scorer
      scorer = Braintrust::Eval::Functions.scorer(
        project: @project_name,
        slug: function_slug,
        state: state
      )

      # Simple task that uppercases
      task = ->(input) { input.upcase }

      # Use remote scorer in Eval.run
      result = Braintrust::Eval.run(
        project: @project_name,
        experiment: "test-ruby-sdk-remote-scorer-eval",
        cases: [
          {input: "hello", expected: "HELLO"},
          {input: "world", expected: "WORLD"}
        ],
        task: task,
        scorers: [scorer],
        api: api,
        quiet: true
      )

      # Should complete successfully
      assert_instance_of Braintrust::Eval::Result, result
      assert result.duration > 0

      # Verify no errors occurred
      assert_equal 0, result.errors.length, "Remote scorer should not error"
    end
  end
end
