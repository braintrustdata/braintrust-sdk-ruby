# frozen_string_literal: true

require "test_helper"
require "braintrust/eval"
require "braintrust/eval/functions"

class Braintrust::Eval::FunctionsTest < Minitest::Test
  def setup
    flunk "BRAINTRUST_API_KEY not set" unless ENV["BRAINTRUST_API_KEY"]

    @state = Braintrust.init(set_global: false, blocking_login: true)
    @api = Braintrust::API.new(state: @state)
    @project_name = "ruby-sdk-test"
  end

  def test_functions_task_returns_callable
    # This test verifies that Functions.task returns a callable object
    # The callable should accept an input and invoke the remote function
    function_slug = unique_name("task-callable")

    # Create a simple remote function
    @api.functions.create(
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
      state: @state
    )

    # Should be callable
    assert_respond_to task, :call
  end

  def test_functions_task_invokes_remote
    # This test verifies that calling the task actually invokes the remote function
    function_slug = unique_name("task-invoke")

    # Create a simple remote function
    @api.functions.create(
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
      state: @state
    )

    result = task.call("world")

    # Should return output from remote function
    assert_instance_of String, result
    assert result.length > 0
  end

  def test_functions_scorer_returns_scorer
    # This test verifies that Functions.scorer returns a Scorer object
    function_slug = unique_name("scorer-test")

    # Create a simple remote scorer
    @api.functions.create(
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
      state: @state
    )

    # Should be a Scorer instance
    assert_instance_of Braintrust::Eval::Scorer, scorer
    assert_equal function_slug, scorer.name
  end

  def test_use_remote_task_in_eval_run
    # This test verifies that remote tasks can be used in Eval.run
    # This is the main use case: calling server-side prompts in evals
    function_slug = unique_name("eval-task")

    # Create a remote function that uppercases input
    @api.functions.create(
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
      state: @state
    )

    # Use in Eval.run with a simple exact match scorer
    result = Braintrust::Eval.run(
      project: @project_name,
      experiment: unique_name("remote-task-eval"),
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
      state: @state,
      quiet: true
    )

    # Should complete successfully
    assert_instance_of Braintrust::Eval::Result, result
    assert result.duration > 0
  end
end
