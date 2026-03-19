# frozen_string_literal: true

require "test_helper"
require "braintrust/task"
require "braintrust/scorer"

class Braintrust::Internal::CallableTest < Minitest::Test
  # ============================================
  # Keyword filtering (block with subset of kwargs, no **)
  # ============================================

  def test_keyword_block_receives_only_declared_kwargs
    received = nil
    scorer = Braintrust::Scorer.new("subset") do |output:, expected:|
      received = {output: output, expected: expected}
      1.0
    end

    scorer.call(
      input: "apple", expected: "fruit", output: "fruit",
      metadata: {key: "val"}, tags: ["t1"]
    )

    assert_equal({output: "fruit", expected: "fruit"}, received)
  end

  def test_keyword_block_with_single_kwarg
    task = Braintrust::Task.new("single") { |input:| input.upcase }

    result = task.call(input: "hello", metadata: {}, tags: nil)

    assert_equal "HELLO", result
  end

  # ============================================
  # Keyrest passthrough (block with **)
  # ============================================

  def test_keyrest_block_receives_all_kwargs
    received = nil
    scorer = Braintrust::Scorer.new("all") do |output:, expected:, **rest|
      received = rest
      1.0
    end

    scorer.call(input: "a", expected: "b", output: "c", metadata: {}, tags: ["t"])

    assert_equal({input: "a", metadata: {}, tags: ["t"]}, received)
  end

  def test_bare_keyrest_receives_everything
    received = nil
    scorer = Braintrust::Scorer.new("bare") do |**kw|
      received = kw
      1.0
    end

    scorer.call(input: "a", expected: "b", output: "c")

    assert_equal({input: "a", expected: "b", output: "c"}, received)
  end

  # ============================================
  # Positional delegation
  # ============================================

  def test_positional_task_block_auto_wrapped
    suppress_logs do
      task = Braintrust::Task.new("pos") { |input| input.upcase }

      result = task.call(input: "hello", metadata: {}, tags: nil)

      assert_equal "HELLO", result
    end
  end

  def test_positional_scorer_block_arity_3
    suppress_logs do
      scorer = Braintrust::Scorer.new("pos3") { |i, e, o| (o == e) ? 1.0 : 0.0 }

      assert_equal [{score: 1.0, metadata: nil, name: "pos3"}],
        scorer.call(input: "a", expected: "b", output: "b", metadata: {})
    end
  end

  def test_positional_scorer_block_arity_4
    suppress_logs do
      scorer = Braintrust::Scorer.new("pos4") { |i, e, o, m| m[:threshold] }

      assert_equal [{score: 0.9, metadata: nil, name: "pos4"}],
        scorer.call(input: "a", expected: "b", output: "c", metadata: {threshold: 0.9})
    end
  end

  # ============================================
  # Zero arity
  # ============================================

  def test_zero_arity_block_passes_through
    scorer = Braintrust::Scorer.new("zero") { 42 }

    assert_equal [{score: 42, metadata: nil, name: "zero"}],
      scorer.call(input: "a", expected: "b", output: "c")
  end

  # ============================================
  # Default naming
  # ============================================

  def test_task_default_name_is_task
    task = Braintrust::Task.new { |input:| input }
    assert_equal "task", task.name
  end

  def test_scorer_default_name_is_scorer
    scorer = Braintrust::Scorer.new { |**| 1.0 }
    assert_equal "scorer", scorer.name
  end

  def test_subclass_name_derived_from_class
    klass = Class.new do
      include Braintrust::Scorer

      def call(**)
        1.0
      end
    end

    Braintrust.stub_const(:FuzzyMatch, klass) do
      scorer = klass.new
      assert_equal "fuzzy_match", scorer.name
    end
  end

  def test_explicit_name_takes_precedence
    task = Braintrust::Task.new("custom") { |input:| input }
    assert_equal "custom", task.name
  end

  # ============================================
  # Subclass with call override (no block)
  # ============================================

  def test_subclass_call_override_filters_extra_kwargs
    klass = Class.new do
      include Braintrust::Scorer

      def call(output:, expected:)
        (output == expected) ? 1.0 : 0.0
      end
    end

    scorer = klass.new
    # KeywordFilter strips extra kwargs (input:, metadata:, tags:) before calling user's #call
    assert_equal [{score: 1.0, metadata: nil, name: "scorer"}],
      scorer.call(input: "a", expected: "b", output: "b", metadata: {}, tags: [])
  end

  # ============================================
  # Error cases
  # ============================================

  def test_no_call_raises_without_block_or_override
    klass = Class.new do
      include Braintrust::Scorer
    end
    scorer = klass.new

    assert_raises(NoMethodError) { scorer.call(output: "a") }
  end

  def test_invalid_positional_arity_raises_for_task
    assert_raises(ArgumentError) do
      Braintrust::Task.new("bad") { |a, b| a }
    end
  end

  def test_invalid_positional_arity_raises_for_scorer
    assert_raises(ArgumentError) do
      Braintrust::Scorer.new("bad") { |a, b| a }
    end
  end
end

# Direct unit tests for ResultNormalizer prepend behavior.
class Braintrust::Scorer::Callable::ResultNormalizerTest < Minitest::Test
  # Build a minimal class with ResultNormalizer prepended and a controllable #call return.
  def make_scorer(name, &block)
    klass = Class.new do
      prepend Braintrust::Scorer::Callable::ResultNormalizer

      define_method(:name) { name }
      define_method(:call) { |**| instance_exec(&block) }
    end
    klass.new
  end

  # ============================================
  # Scalar return (else branch)
  # ============================================

  def test_scalar_float_wrapped
    scorer = make_scorer("s") { 0.9 }
    assert_equal [{score: 0.9, metadata: nil, name: "s"}], scorer.call
  end

  def test_scalar_integer_wrapped
    scorer = make_scorer("s") { 1 }
    assert_equal [{score: 1, metadata: nil, name: "s"}], scorer.call
  end

  def test_scalar_nil_raises
    scorer = make_scorer("s") { nil }
    assert_raises(ArgumentError) { scorer.call }
  end

  def test_scalar_boolean_raises
    scorer = make_scorer("s") { true }
    assert_raises(ArgumentError) { scorer.call }
  end

  def test_hash_with_nil_score_raises
    scorer = make_scorer("s") { {score: nil} }
    assert_raises(ArgumentError) { scorer.call }
  end

  def test_array_item_with_nil_score_raises
    scorer = make_scorer("s") { [{name: "a", score: 1.0}, {name: "b", score: nil}] }
    assert_raises(ArgumentError) { scorer.call }
  end

  # ============================================
  # Hash return
  # ============================================

  def test_hash_without_name_gets_scorer_name
    scorer = make_scorer("my_scorer") { {score: 0.5} }
    assert_equal [{score: 0.5, name: "my_scorer"}], scorer.call
  end

  def test_hash_with_name_preserves_name
    scorer = make_scorer("my_scorer") { {score: 0.5, name: "override"} }
    assert_equal [{score: 0.5, name: "override"}], scorer.call
  end

  def test_hash_with_metadata_preserved
    scorer = make_scorer("s") { {score: 0.8, metadata: {reason: "close"}} }
    assert_equal [{score: 0.8, metadata: {reason: "close"}, name: "s"}], scorer.call
  end

  # ============================================
  # Array return
  # ============================================

  def test_array_items_passed_through
    scorer = make_scorer("s") { [{name: "a", score: 1.0}, {name: "b", score: 0.5}] }
    assert_equal [{name: "a", score: 1.0}, {name: "b", score: 0.5}], scorer.call
  end

  def test_array_items_without_name_get_scorer_name
    scorer = make_scorer("my_scorer") { [{score: 1.0}, {score: 0.5}] }
    assert_equal [{score: 1.0, name: "my_scorer"}, {score: 0.5, name: "my_scorer"}], scorer.call
  end

  def test_array_items_mixed_name_presence
    scorer = make_scorer("fallback") { [{name: "explicit", score: 1.0}, {score: 0.5}] }
    assert_equal [{name: "explicit", score: 1.0}, {score: 0.5, name: "fallback"}], scorer.call
  end

  def test_empty_array_returns_empty_array
    scorer = make_scorer("s") { [] }
    assert_equal [], scorer.call
  end

  # ============================================
  # Always returns Array
  # ============================================

  def test_result_is_always_array
    [0.5, {score: 1.0}, [{score: 0.9}]].each do |raw|
      scorer = make_scorer("s") { raw }
      assert_instance_of Array, scorer.call
    end
  end
end

# Direct unit tests for KeywordFilter class methods and instance behavior.
class Braintrust::Internal::Callable::KeywordFilterTest < Minitest::Test
  # ============================================
  # .filter
  # ============================================

  def test_filter_slices_to_declared_keys
    params = [[:keyreq, :output], [:keyreq, :expected]]
    kwargs = {input: "a", expected: "b", output: "c", metadata: {}}

    assert_equal({expected: "b", output: "c"}, Braintrust::Internal::Callable::KeywordFilter.filter(params, kwargs))
  end

  def test_filter_includes_optional_keywords
    params = [[:keyreq, :output], [:key, :metadata]]
    kwargs = {input: "a", output: "c", metadata: {}, tags: []}

    assert_equal({output: "c", metadata: {}}, Braintrust::Internal::Callable::KeywordFilter.filter(params, kwargs))
  end

  def test_filter_returns_all_kwargs_when_keyrest_present
    params = [[:keyreq, :output], [:keyrest, :rest]]
    kwargs = {input: "a", output: "c", extra: true}

    assert_equal kwargs, Braintrust::Internal::Callable::KeywordFilter.filter(params, kwargs)
  end

  def test_filter_returns_empty_when_no_declared_keywords
    params = []
    kwargs = {input: "a", output: "c"}

    assert_equal({}, Braintrust::Internal::Callable::KeywordFilter.filter(params, kwargs))
  end

  def test_filter_handles_missing_keys_gracefully
    params = [[:keyreq, :output], [:keyreq, :expected]]
    kwargs = {output: "c"}

    assert_equal({output: "c"}, Braintrust::Internal::Callable::KeywordFilter.filter(params, kwargs))
  end

  # ============================================
  # .wrap_block
  # ============================================

  def test_wrap_block_filters_kwargs_for_subset_block
    block = ->(output:, expected:) { [output, expected] }
    wrapped = Braintrust::Internal::Callable::KeywordFilter.wrap_block(block)

    assert_equal ["c", "b"], wrapped.call(input: "a", expected: "b", output: "c", metadata: {})
  end

  def test_wrap_block_returns_original_when_keyrest
    block = ->(output:, **rest) { rest }
    wrapped = Braintrust::Internal::Callable::KeywordFilter.wrap_block(block)

    assert_same block, wrapped
  end

  def test_wrap_block_returns_original_for_bare_keyrest
    block = ->(**kw) { kw }
    wrapped = Braintrust::Internal::Callable::KeywordFilter.wrap_block(block)

    assert_same block, wrapped
  end

  # ============================================
  # .has_keyword_splat?
  # ============================================

  def test_has_keyword_splat_true_for_keyrest
    assert Braintrust::Internal::Callable::KeywordFilter.has_keyword_splat?([[:keyreq, :a], [:keyrest, :rest]])
  end

  def test_has_keyword_splat_false_for_keywords_only
    refute Braintrust::Internal::Callable::KeywordFilter.has_keyword_splat?([[:keyreq, :a], [:key, :b]])
  end

  def test_has_keyword_splat_false_for_empty
    refute Braintrust::Internal::Callable::KeywordFilter.has_keyword_splat?([])
  end

  # ============================================
  # .has_any_keywords?
  # ============================================

  def test_has_any_keywords_true_for_keyreq
    assert Braintrust::Internal::Callable::KeywordFilter.has_any_keywords?([[:keyreq, :a]])
  end

  def test_has_any_keywords_true_for_optional_key
    assert Braintrust::Internal::Callable::KeywordFilter.has_any_keywords?([[:key, :a]])
  end

  def test_has_any_keywords_true_for_keyrest
    assert Braintrust::Internal::Callable::KeywordFilter.has_any_keywords?([[:keyrest, :rest]])
  end

  def test_has_any_keywords_false_for_positional_only
    refute Braintrust::Internal::Callable::KeywordFilter.has_any_keywords?([[:req, :a], [:opt, :b]])
  end

  def test_has_any_keywords_false_for_empty
    refute Braintrust::Internal::Callable::KeywordFilter.has_any_keywords?([])
  end

  # ============================================
  # #call instance method (prepend behavior)
  # ============================================

  def test_call_filters_via_super_method_introspection
    klass = Class.new do
      prepend Braintrust::Internal::Callable::KeywordFilter

      def call(output:, expected:)
        {output: output, expected: expected}
      end
    end

    result = klass.new.call(output: "c", expected: "b", input: "a", metadata: {})
    assert_equal({output: "c", expected: "b"}, result)
  end

  def test_call_filters_via_call_parameters_protocol
    klass = Class.new do
      prepend Braintrust::Internal::Callable::KeywordFilter

      def call(**kwargs)
        kwargs
      end

      def call_parameters
        [[:keyreq, :output]]
      end
    end

    result = klass.new.call(output: "c", input: "a", metadata: {})
    assert_equal({output: "c"}, result)
  end

  def test_call_prefers_call_parameters_over_super_method
    klass = Class.new do
      prepend Braintrust::Internal::Callable::KeywordFilter

      def call(**kwargs)
        kwargs
      end

      # call_parameters restricts to just output:, even though
      # super_method would see **kwargs (keyrest)
      def call_parameters
        [[:keyreq, :output]]
      end
    end

    result = klass.new.call(output: "c", expected: "b", input: "a", metadata: {})
    assert_equal({output: "c"}, result)
  end

  def test_call_passes_all_when_super_method_has_keyrest
    klass = Class.new do
      prepend Braintrust::Internal::Callable::KeywordFilter

      def call(**kwargs)
        kwargs
      end
    end

    result = klass.new.call(output: "c", input: "a")
    assert_equal({output: "c", input: "a"}, result)
  end
end
