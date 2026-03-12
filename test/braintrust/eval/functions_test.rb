# frozen_string_literal: true

require "test_helper"
require "braintrust/eval"

class Braintrust::Eval::FunctionsTest < Minitest::Test
  def test_task_delegates_to_braintrust_functions
    sentinel = Object.new
    kwargs = nil
    delegate = ->(**kw) do
      kwargs = kw
      sentinel
    end
    Braintrust::Functions.stub(:task, delegate) do
      result = suppress_logs { Braintrust::Eval::Functions.task(project: "proj", slug: "fn") }
      assert_same sentinel, result
      assert_equal({project: "proj", slug: "fn"}, kwargs)
    end
  end

  def test_task_logs_deprecation_warning
    Braintrust::Functions.stub(:task, ->(**) {}) do
      assert_warns_once(:eval_functions_task, /Braintrust::Functions\.task/) do
        Braintrust::Eval::Functions.task(project: "proj", slug: "fn")
      end
    end
  end

  def test_scorer_delegates_to_braintrust_functions
    sentinel = Object.new
    kwargs = nil
    delegate = ->(**kw) do
      kwargs = kw
      sentinel
    end
    Braintrust::Functions.stub(:scorer, delegate) do
      result = suppress_logs { Braintrust::Eval::Functions.scorer(project: "proj", slug: "fn") }
      assert_same sentinel, result
      assert_equal({project: "proj", slug: "fn"}, kwargs)
    end
  end

  def test_scorer_logs_deprecation_warning
    Braintrust::Functions.stub(:scorer, ->(**) {}) do
      assert_warns_once(:eval_functions_scorer, /Braintrust::Functions\.scorer/) do
        Braintrust::Eval::Functions.scorer(project: "proj", slug: "fn")
      end
    end
  end
end
