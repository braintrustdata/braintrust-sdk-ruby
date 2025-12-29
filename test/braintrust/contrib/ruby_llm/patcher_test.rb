# frozen_string_literal: true

require "test_helper"

# Explicitly load the patcher (lazy-loaded by integration)
require "braintrust/contrib/ruby_llm/patcher"

class Braintrust::Contrib::RubyLLM::ChatPatcherTest < Minitest::Test
  def setup
    skip "RubyLLM gem not available" unless defined?(::RubyLLM)
  end

  # --- .applicable? ---

  def test_applicable_returns_true_when_ruby_llm_chat_defined
    assert Braintrust::Contrib::RubyLLM::ChatPatcher.applicable?
  end

  # --- .patched? ---

  def test_patched_returns_false_when_not_patched
    fake_chat_class = Class.new

    ::RubyLLM.stub_const(:Chat, fake_chat_class) do
      refute Braintrust::Contrib::RubyLLM::ChatPatcher.patched?
    end
  end

  def test_patched_returns_true_when_module_included
    fake_chat_class = Class.new do
      include Braintrust::Contrib::RubyLLM::Instrumentation::Chat
    end

    ::RubyLLM.stub_const(:Chat, fake_chat_class) do
      assert Braintrust::Contrib::RubyLLM::ChatPatcher.patched?
    end
  end

  def test_patched_returns_false_for_unpatched_instance
    fake_singleton = Class.new

    mock_chain(:singleton_class, returns: fake_singleton) do |chat|
      refute Braintrust::Contrib::RubyLLM::ChatPatcher.patched?(target: chat)
    end
  end

  def test_patched_returns_true_for_patched_instance
    fake_singleton = Class.new do
      include Braintrust::Contrib::RubyLLM::Instrumentation::Chat
    end

    mock_chain(:singleton_class, returns: fake_singleton) do |chat|
      assert Braintrust::Contrib::RubyLLM::ChatPatcher.patched?(target: chat)
    end
  end

  # --- .perform_patch ---

  def test_perform_patch_includes_module_for_class_level
    fake_chat_class = Minitest::Mock.new
    fake_chat_class.expect(:include, true, [Braintrust::Contrib::RubyLLM::Instrumentation::Chat])

    ::RubyLLM.stub_const(:Chat, fake_chat_class) do
      Braintrust::Contrib::RubyLLM::ChatPatcher.perform_patch
      fake_chat_class.verify
    end
  end

  def test_perform_patch_includes_module_for_instance_level
    terminal = Minitest::Mock.new
    terminal.expect(:include, true, [Braintrust::Contrib::RubyLLM::Instrumentation::Chat])

    mock_chain(:singleton_class, returns: terminal) do |chat|
      chat.expect(:is_a?, true, [::RubyLLM::Chat])
      Braintrust::Contrib::RubyLLM::ChatPatcher.perform_patch(target: chat)
    end
    terminal.verify
  end

  def test_perform_patch_raises_for_invalid_target
    fake_chat = Minitest::Mock.new
    fake_chat.expect(:is_a?, false, [::RubyLLM::Chat])

    assert_raises(ArgumentError) do
      Braintrust::Contrib::RubyLLM::ChatPatcher.perform_patch(target: fake_chat)
    end

    fake_chat.verify
  end
end
