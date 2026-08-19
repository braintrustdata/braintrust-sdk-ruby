# frozen_string_literal: true

require "test_helper"
require_relative "integration_helper"
require "braintrust/contrib/llm_rb/patcher"

class Braintrust::Contrib::LlmRb::ContextPatcherTest < Minitest::Test
  include Braintrust::Contrib::LlmRb::IntegrationHelper

  def setup
    skip_unless_llm_rb!
  end

  def test_applicable_when_llm_context_defined
    assert Braintrust::Contrib::LlmRb::ContextPatcher.applicable?
  end

  # --- .patched? ---

  def test_patched_returns_false_for_unpatched_class
    fake_ctx_class = Class.new

    ::LLM.stub_const(:Context, fake_ctx_class) do
      refute Braintrust::Contrib::LlmRb::ContextPatcher.patched?
    end
  end

  def test_patched_returns_true_when_module_included
    fake_ctx_class = Class.new do
      include Braintrust::Contrib::LlmRb::Instrumentation::Context
    end

    ::LLM.stub_const(:Context, fake_ctx_class) do
      assert Braintrust::Contrib::LlmRb::ContextPatcher.patched?
    end
  end

  def test_patched_returns_false_for_unpatched_instance
    fake_singleton = Class.new

    mock_chain(:singleton_class, returns: fake_singleton) do |ctx|
      refute Braintrust::Contrib::LlmRb::ContextPatcher.patched?(target: ctx)
    end
  end

  def test_patched_returns_true_for_patched_instance
    fake_singleton = Class.new do
      include Braintrust::Contrib::LlmRb::Instrumentation::Context
    end

    mock_chain(:singleton_class, returns: fake_singleton) do |ctx|
      assert Braintrust::Contrib::LlmRb::ContextPatcher.patched?(target: ctx)
    end
  end

  # --- .perform_patch ---

  def test_perform_patch_includes_module_for_class_level
    fake_ctx_class = Minitest::Mock.new
    fake_ctx_class.expect(:include, true, [Braintrust::Contrib::LlmRb::Instrumentation::Context])

    ::LLM.stub_const(:Context, fake_ctx_class) do
      Braintrust::Contrib::LlmRb::ContextPatcher.perform_patch
      fake_ctx_class.verify
    end
  end

  def test_perform_patch_includes_module_for_instance_level
    terminal = Minitest::Mock.new
    terminal.expect(:include, true, [Braintrust::Contrib::LlmRb::Instrumentation::Context])

    mock_chain(:singleton_class, returns: terminal) do |ctx|
      ctx.expect(:is_a?, true, [::LLM::Context])
      Braintrust::Contrib::LlmRb::ContextPatcher.perform_patch(target: ctx)
    end
    terminal.verify
  end

  def test_perform_patch_raises_for_invalid_target
    fake_ctx = Minitest::Mock.new
    fake_ctx.expect(:is_a?, false, [::LLM::Context])

    assert_raises(ArgumentError) do
      Braintrust::Contrib::LlmRb::ContextPatcher.perform_patch(target: fake_ctx)
    end

    fake_ctx.verify
  end
end
