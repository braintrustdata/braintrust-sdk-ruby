# frozen_string_literal: true

require "test_helper"
require_relative "../integration_helper"
require "braintrust/contrib/llm_rb/instrumentation/context"
require "braintrust/contrib/llm_rb/patcher"

class Braintrust::Contrib::LlmRb::Instrumentation::ContextTest < Minitest::Test
  include Braintrust::Contrib::LlmRb::IntegrationHelper

  def setup
    skip_unless_llm_rb!
  end

  # --- .included ---

  def test_included_prepends_instance_methods
    mod = Braintrust::Contrib::LlmRb::Instrumentation::Context

    base = Class.new
    instance_methods_included = false
    base.define_singleton_method(:prepend) do |m|
      instance_methods_included = true if m == mod::InstanceMethods
    end
    base.define_singleton_method(:ancestors) { [] }

    mod.included(base)

    assert instance_methods_included
  end

  def test_included_skips_prepend_when_already_applied
    base = Class.new do
      include Braintrust::Contrib::LlmRb::Instrumentation::Context
    end

    # Should not raise or double-prepend
    Braintrust::Contrib::LlmRb::Instrumentation::Context.included(base)

    count = base.ancestors.count { |a| a == Braintrust::Contrib::LlmRb::Instrumentation::Context::InstanceMethods }
    assert_equal 1, count
  end

  # --- .applied? ---

  def test_applied_returns_false_when_not_included
    base = Class.new
    refute Braintrust::Contrib::LlmRb::Instrumentation::Context.applied?(base)
  end

  def test_applied_returns_true_when_included
    base = Class.new do
      include Braintrust::Contrib::LlmRb::Instrumentation::Context
    end
    assert Braintrust::Contrib::LlmRb::Instrumentation::Context.applied?(base)
  end
end

# E2E tests for Context instrumentation
class Braintrust::Contrib::LlmRb::Instrumentation::ContextE2ETest < Minitest::Test
  include Braintrust::Contrib::LlmRb::IntegrationHelper

  def setup
    skip_unless_llm_rb!
    # Reset the patcher state to avoid cross-test pollution
    Braintrust::Contrib::LlmRb::ContextPatcher.reset!
  end

  def teardown
    Braintrust::Contrib::LlmRb::ContextPatcher.reset!
  end

  def make_llm
    LLM.openai(key: get_openai_key)
  end

  # --- basic chat ---

  def test_talk_creates_span_with_correct_name
    VCR.use_cassette("contrib/llm_rb/basic_chat") do
      rig = setup_otel_test_rig
      llm = make_llm
      ctx = LLM::Context.new(llm)

      Braintrust.instrument!(:llm_rb, target: ctx, tracer_provider: rig.tracer_provider)

      res = ctx.talk("Say 'test'")
      refute_nil res

      span = rig.drain_one
      assert_equal "llm_rb.chat", span.name
    end
  end

  def test_talk_captures_input_json
    VCR.use_cassette("contrib/llm_rb/basic_chat") do
      rig = setup_otel_test_rig
      llm = make_llm
      ctx = LLM::Context.new(llm)

      Braintrust.instrument!(:llm_rb, target: ctx, tracer_provider: rig.tracer_provider)
      ctx.talk("Say 'test'")

      span = rig.drain_one
      assert span.attributes.key?("braintrust.input_json"), "Should have braintrust.input_json"

      input = JSON.parse(span.attributes["braintrust.input_json"])
      assert input.is_a?(Array)
      assert_equal 1, input.length
      assert_equal "user", input[0]["role"]
      assert_equal "Say 'test'", input[0]["content"]
    end
  end

  def test_talk_captures_output_json
    VCR.use_cassette("contrib/llm_rb/basic_chat") do
      rig = setup_otel_test_rig
      llm = make_llm
      ctx = LLM::Context.new(llm)

      Braintrust.instrument!(:llm_rb, target: ctx, tracer_provider: rig.tracer_provider)
      ctx.talk("Say 'test'")

      span = rig.drain_one
      assert span.attributes.key?("braintrust.output_json"), "Should have braintrust.output_json"

      output = JSON.parse(span.attributes["braintrust.output_json"])
      assert output.is_a?(Array)
      assert output.length > 0
      assert_equal "assistant", output[0]["role"]
      refute_nil output[0]["content"]
    end
  end

  def test_talk_captures_metadata
    VCR.use_cassette("contrib/llm_rb/basic_chat") do
      rig = setup_otel_test_rig
      llm = make_llm
      ctx = LLM::Context.new(llm)

      Braintrust.instrument!(:llm_rb, target: ctx, tracer_provider: rig.tracer_provider)
      ctx.talk("Say 'test'")

      span = rig.drain_one
      assert span.attributes.key?("braintrust.metadata"), "Should have braintrust.metadata"

      metadata = JSON.parse(span.attributes["braintrust.metadata"])
      assert_equal "llm_rb", metadata["provider"]
      assert_equal "openai", metadata["llm_provider"]
      refute_nil metadata["model"]
    end
  end

  def test_talk_captures_token_metrics
    VCR.use_cassette("contrib/llm_rb/basic_chat") do
      rig = setup_otel_test_rig
      llm = make_llm
      ctx = LLM::Context.new(llm)

      Braintrust.instrument!(:llm_rb, target: ctx, tracer_provider: rig.tracer_provider)
      ctx.talk("Say 'test'")

      span = rig.drain_one
      assert span.attributes.key?("braintrust.metrics"), "Should have braintrust.metrics"

      metrics = JSON.parse(span.attributes["braintrust.metrics"])
      assert metrics["prompt_tokens"] > 0, "Should have prompt_tokens"
      assert metrics["completion_tokens"] > 0, "Should have completion_tokens"
      assert metrics["tokens"] > 0, "Should have total tokens"
    end
  end

  def test_talk_does_not_change_return_value
    VCR.use_cassette("contrib/llm_rb/basic_chat") do
      rig = setup_otel_test_rig
      llm = make_llm
      ctx = LLM::Context.new(llm)

      Braintrust.instrument!(:llm_rb, target: ctx, tracer_provider: rig.tracer_provider)

      res = ctx.talk("Say 'test'")

      refute_nil res
      assert res.respond_to?(:choices), "Response should have choices method"
      assert res.respond_to?(:usage), "Response should have usage method"
    end
  end

  # --- multi-turn conversation ---

  def test_multi_turn_includes_history_in_input
    VCR.use_cassette("contrib/llm_rb/multi_turn_chat") do
      rig = setup_otel_test_rig
      llm = make_llm
      ctx = LLM::Context.new(llm)

      Braintrust.instrument!(:llm_rb, target: ctx, tracer_provider: rig.tracer_provider)

      ctx.talk("Hello")
      ctx.talk("What is 2+2?")

      spans = rig.drain
      assert_equal 2, spans.length

      # Second span should include the first turn's messages
      second_span = spans.last
      input = JSON.parse(second_span.attributes["braintrust.input_json"])
      assert input.length >= 3, "Second turn should include history: #{input.inspect}"

      roles = input.map { |m| m["role"] }
      assert_includes roles, "user"
      assert_includes roles, "assistant"
    end
  end

  # --- error handling ---

  def test_talk_records_exception_on_error
    VCR.use_cassette("contrib/llm_rb/error_chat") do
      rig = setup_otel_test_rig
      llm = LLM.openai(key: "invalid-key")
      ctx = LLM::Context.new(llm)

      Braintrust.instrument!(:llm_rb, target: ctx, tracer_provider: rig.tracer_provider)

      assert_raises(LLM::Error) { ctx.talk("Hello") }

      span = rig.drain_one
      assert_equal "llm_rb.chat", span.name

      # Span should have error status
      assert_equal ::OpenTelemetry::Trace::Status::ERROR, span.status.code
    end
  end

  # --- class-level vs instance-level patching ---

  def test_instance_level_patching_only_affects_target
    VCR.use_cassette("contrib/llm_rb/basic_chat") do
      rig = setup_otel_test_rig
      llm = make_llm
      ctx1 = LLM::Context.new(llm)

      # Only instrument ctx1
      Braintrust.instrument!(:llm_rb, target: ctx1, tracer_provider: rig.tracer_provider)

      ctx1.talk("Say 'test'")

      spans = rig.drain
      assert_equal 1, spans.length, "Only instrumented context should produce spans"
    end
  end
end
