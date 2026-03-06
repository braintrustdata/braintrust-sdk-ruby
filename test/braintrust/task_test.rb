# frozen_string_literal: true

require "test_helper"
require "braintrust/task"

class Braintrust::TaskTest < Minitest::Test
  # ============================================
  # Task.new with block (inline tasks)
  # ============================================

  def test_task_with_kwargs_block
    task = Braintrust::Task.new("upcase") { |input:, **| input.upcase }

    assert_equal "upcase", task.name
    assert_equal "HELLO", task.call(input: "hello")
  end

  def test_task_with_subset_kwargs_filters_extra_keys
    # Block declares only input: — no **
    task = Braintrust::Task.new("subset") { |input:| input.upcase }

    # Calling with extra kwargs should not raise
    assert_equal "HELLO", task.call(input: "hello", metadata: {}, tags: ["t1"])
  end

  def test_task_with_keyrest_receives_all_kwargs
    received = nil
    task = Braintrust::Task.new("all") do |**kw|
      received = kw
      "done"
    end

    task.call(input: "a", metadata: {key: "val"}, tags: ["t"])

    assert_equal({input: "a", metadata: {key: "val"}, tags: ["t"]}, received)
  end

  def test_task_with_legacy_1_param_block
    suppress_logs do
      task = Braintrust::Task.new("pos") { |input| input.upcase }

      assert_equal "pos", task.name
      assert_equal "HELLO", task.call(input: "hello", metadata: {})
    end
  end

  def test_task_return_value_passes_through
    task = Braintrust::Task.new("hash") { |input:| {result: input.upcase, length: input.length} }

    assert_equal({result: "HELLO", length: 5}, task.call(input: "hello"))
  end

  def test_task_zero_arity_block
    task = Braintrust::Task.new("zero") { 42 }

    assert_equal 42, task.call(input: "anything")
  end

  # ============================================
  # Validation
  # ============================================

  def test_task_without_block_or_override_raises_on_call
    klass = Class.new do
      include Braintrust::Task
    end
    task = klass.new

    assert_raises(NoMethodError) do
      task.call(input: "a")
    end
  end

  def test_task_invalid_arity_raises
    error = assert_raises(ArgumentError) do
      Braintrust::Task.new("bad") { |a, b| a }
    end

    assert_match(/task must accept keyword args or 1 positional param/i, error.message)
  end

  def test_task_invalid_arity_3_raises
    assert_raises(ArgumentError) do
      Braintrust::Task.new("bad") { |a, b, c| a }
    end
  end

  # ============================================
  # Name detection
  # ============================================

  def test_task_name_defaults_to_task
    task = Braintrust::Task.new { |input:| input }
    assert_equal "task", task.name
  end

  def test_task_explicit_name_takes_precedence
    task = Braintrust::Task.new("my_task") { |input:| input }
    assert_equal "my_task", task.name
  end

  def test_subclass_name_derived_from_class_name
    klass = Class.new do
      include Braintrust::Task

      def call(input:)
        input.upcase
      end
    end

    Braintrust.stub_const(:TextProcessor, klass) do
      task = klass.new
      assert_equal "text_processor", task.name
    end
  end

  def test_subclass_name_override
    klass = Class.new do
      include Braintrust::Task

      def name
        "custom_name"
      end

      def call(input:)
        input
      end
    end

    task = klass.new
    assert_equal "custom_name", task.name
  end

  # ============================================
  # Subclass pattern (include Task)
  # ============================================

  def test_subclass_with_call_override
    klass = Class.new do
      include Braintrust::Task

      def call(input:)
        input.upcase
      end
    end

    task = klass.new
    assert_kind_of Braintrust::Task, task

    # KeywordFilter strips extra kwargs
    assert_equal "HELLO", task.call(input: "hello", metadata: {}, tags: [])
  end

  def test_subclass_with_multiple_kwargs
    klass = Class.new do
      include Braintrust::Task

      def call(input:, metadata:)
        "#{input}-#{metadata[:mode]}"
      end
    end

    task = klass.new
    assert_equal "hello-fast", task.call(input: "hello", metadata: {mode: "fast"}, tags: [])
  end

  def test_subclass_with_instance_state
    klass = Class.new do
      include Braintrust::Task

      def initialize(prefix)
        @prefix = prefix
      end

      def call(input:)
        "#{@prefix}: #{input}"
      end
    end

    task = klass.new("Result")
    assert_equal "Result: hello", task.call(input: "hello")
  end

  # ============================================
  # Type checking (Task === instance)
  # ============================================

  def test_block_task_satisfies_module_check
    task = Braintrust::Task.new("t") { |input:| input }
    assert_kind_of Braintrust::Task, task
  end

  def test_subclass_task_satisfies_module_check
    klass = Class.new do
      include Braintrust::Task

      def call(input:) = input
    end

    assert_kind_of Braintrust::Task, klass.new
  end

  def test_case_when_matches_task
    task = Braintrust::Task.new("t") { |input:| input }

    matched = case task
    when Braintrust::Task then true
    else false
    end

    assert matched
  end

  # ============================================
  # call_parameters protocol
  # ============================================

  def test_block_task_exposes_call_parameters
    task = Braintrust::Task.new("t") { |input:, metadata:| input }

    params = task.call_parameters
    param_names = params.filter_map { |type, name| name if type == :keyreq }

    assert_includes param_names, :input
    assert_includes param_names, :metadata
  end
end
