# frozen_string_literal: true

require "test_helper"
require "braintrust/remote"

class Braintrust::Remote::EvalRunnerTest < Minitest::Test
  def setup
    Braintrust::Remote.clear_evaluators!
  end

  def teardown
    Braintrust::Remote.clear_evaluators!
  end

  # ============================================
  # Constructor tests
  # ============================================

  def test_initializes_with_evaluator_and_state
    evaluator = create_simple_evaluator
    state = mock_state

    runner = Braintrust::Remote::EvalRunner.new(evaluator, state: state)

    assert_equal evaluator, runner.evaluator
    assert_equal state, runner.state
  end

  def test_initializes_with_parameters
    evaluator = create_evaluator_with_params
    state = mock_state

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      parameters: {model: "gpt-3.5-turbo"}
    )

    assert_equal "gpt-3.5-turbo", runner.parameters[:model]
  end

  def test_validates_parameters_with_defaults
    evaluator = create_evaluator_with_params
    state = mock_state

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      parameters: {} # Empty params should use defaults
    )

    assert_equal "gpt-4", runner.parameters[:model]
  end

  # ============================================
  # run tests
  # ============================================

  def test_run_executes_task_for_each_case
    evaluator = create_simple_evaluator
    state = mock_state

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      no_send_logs: true # Skip experiment creation
    )

    data = [
      Braintrust::Remote::EvalCase.new(input: "hello", expected: "HELLO"),
      Braintrust::Remote::EvalCase.new(input: "world", expected: "WORLD")
    ]

    summary = runner.run(data: data)

    assert_equal 2, summary[:results].length
    assert_equal "HELLO", summary[:results][0][:output]
    assert_equal "WORLD", summary[:results][1][:output]
  end

  def test_run_executes_scorers
    evaluator = create_evaluator_with_scorer
    state = mock_state

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      no_send_logs: true
    )

    data = [
      Braintrust::Remote::EvalCase.new(input: "hello", expected: "HELLO")
    ]

    summary = runner.run(data: data)

    assert summary[:results][0][:scores].key?("exact_match")
    assert_equal 1.0, summary[:results][0][:scores]["exact_match"][:score]
  end

  def test_run_aggregates_scores_in_summary
    evaluator = create_evaluator_with_scorer
    state = mock_state

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      no_send_logs: true
    )

    data = [
      Braintrust::Remote::EvalCase.new(input: "hello", expected: "HELLO"), # match
      Braintrust::Remote::EvalCase.new(input: "world", expected: "WRONG")  # no match
    ]

    summary = runner.run(data: data)

    assert summary[:scores].key?("exact_match")
    assert_equal 0.5, summary[:scores]["exact_match"][:score] # 1/2 matched
  end

  def test_run_handles_task_errors
    evaluator = Braintrust::Remote::Evaluator.new("ErrorEval") do
      task { |input| raise "Task failed!" }
    end
    state = mock_state

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      no_send_logs: true
    )

    data = [Braintrust::Remote::EvalCase.new(input: "test")]

    summary = runner.run(data: data)

    assert_equal "Task failed!", summary[:results][0][:error]
    assert_nil summary[:results][0][:output]
  end

  def test_run_with_stream_callback
    evaluator = create_simple_evaluator
    state = mock_state
    events = []

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      no_send_logs: true,
      stream_callback: ->(event) { events << event }
    )

    data = [Braintrust::Remote::EvalCase.new(input: "hello", expected: "HELLO")]

    runner.run(data: data)

    # Should have received task completion event
    task_events = events.select { |e| e[:object_type] == "task" }
    assert task_events.length > 0
  end

  def test_run_passes_hooks_to_task
    received_params = nil

    evaluator = Braintrust::Remote::Evaluator.new("HooksEval") do
      parameters do
        string :model, default: "gpt-4"
      end
      task { |input, hooks|
        received_params = hooks.parameters
        input.upcase
      }
    end
    state = mock_state

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      parameters: {model: "claude"},
      no_send_logs: true
    )

    data = [Braintrust::Remote::EvalCase.new(input: "test")]
    runner.run(data: data)

    assert_equal "claude", received_params[:model]
  end

  # ============================================
  # Scorer execution tests
  # ============================================

  def test_run_skips_scorers_on_task_error
    evaluator = Braintrust::Remote::Evaluator.new("ErrorEval") do
      task { |input| raise "Failed" }
      scores [
        ->(input:, output:, expected:, **) { 1.0 }
      ]
    end
    state = mock_state

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      no_send_logs: true
    )

    data = [Braintrust::Remote::EvalCase.new(input: "test")]
    summary = runner.run(data: data)

    assert_equal({}, summary[:results][0][:scores])
  end

  def test_run_handles_scorer_errors
    evaluator = Braintrust::Remote::Evaluator.new("ScorerErrorEval") do
      task { |input| input.upcase }
      scores [
        Braintrust::Remote::InlineScorer.new("failing_scorer") do |**|
          raise "Scorer failed!"
        end
      ]
    end
    state = mock_state

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      no_send_logs: true
    )

    data = [Braintrust::Remote::EvalCase.new(input: "test")]
    summary = runner.run(data: data)

    score_result = summary[:results][0][:scores]["failing_scorer"]
    assert_nil score_result[:score]
    assert_equal "Scorer failed!", score_result[:error]
  end

  # ============================================
  # Extra scorers tests
  # ============================================

  def test_run_with_extra_scorers
    evaluator = create_simple_evaluator
    state = mock_state

    extra_scorer = Braintrust::Remote::InlineScorer.new("extra") do |output:, **|
      (output.length > 0) ? 1.0 : 0.0
    end

    runner = Braintrust::Remote::EvalRunner.new(
      evaluator,
      state: state,
      no_send_logs: true
    )

    data = [Braintrust::Remote::EvalCase.new(input: "hello")]
    summary = runner.run(data: data, extra_scorers: [extra_scorer])

    assert summary[:results][0][:scores].key?("extra")
  end

  private

  def mock_state
    state = Object.new
    state.define_singleton_method(:logged_in) { true }
    state.define_singleton_method(:api_url) { "https://api.braintrust.dev" }
    state.define_singleton_method(:api_key) { "test-key" }
    state.define_singleton_method(:org_name) { "test-org" }
    state.define_singleton_method(:login) { true }
    state
  end

  def create_simple_evaluator
    Braintrust::Remote::Evaluator.new("SimpleEval") do
      task { |input| input.upcase }
    end
  end

  def create_evaluator_with_params
    Braintrust::Remote::Evaluator.new("ParamEval") do
      parameters do
        string :model, default: "gpt-4"
      end
      task { |input| input.upcase }
    end
  end

  def create_evaluator_with_scorer
    Braintrust::Remote::Evaluator.new("ScorerEval") do
      task { |input| input.upcase }
      scores [
        Braintrust::Remote::InlineScorer.new("exact_match") do |output:, expected:, **|
          (output == expected) ? 1.0 : 0.0
        end
      ]
    end
  end
end
