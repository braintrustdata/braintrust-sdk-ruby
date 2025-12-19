# frozen_string_literal: true

require "test_helper"

# Explicitly load the patcher (lazy-loaded by integration)
require "braintrust/contrib/openai/patcher"

class Braintrust::Contrib::OpenAI::PatcherTest < Minitest::Test
  def setup
    # Skip all tests if the OpenAI gem is not available
    skip "OpenAI gem not available" unless defined?(OpenAI)

    # Check which gem is loaded
    if Gem.loaded_specs["ruby-openai"]
      skip "openai gem not available (found ruby-openai gem instead)"
    elsif !Gem.loaded_specs["openai"]
      skip "Could not determine which OpenAI gem is loaded"
    end
  end

  # ChatPatcher tests

  def test_chat_patcher_applicable_returns_true
    assert Braintrust::Contrib::OpenAI::ChatPatcher.applicable?
  end

  def test_chat_patcher_includes_correct_module_for_class_level
    fake_completions = Minitest::Mock.new
    fake_completions.expect(:include, true, [Braintrust::Contrib::OpenAI::Instrumentation::Chat::Completions])

    OpenAI::Resources::Chat.stub_const(:Completions, fake_completions) do
      Braintrust::Contrib::OpenAI::ChatPatcher.perform_patch
      fake_completions.verify
    end
  end

  def test_chat_patcher_includes_correct_module_for_instance_level
    fake_singleton_class = Minitest::Mock.new
    fake_singleton_class.expect(:include, true, [Braintrust::Contrib::OpenAI::Instrumentation::Chat::Completions])

    fake_completions = Minitest::Mock.new
    fake_completions.expect(:singleton_class, fake_singleton_class)

    fake_chat = Minitest::Mock.new
    fake_chat.expect(:completions, fake_completions)

    fake_client = Minitest::Mock.new
    fake_client.expect(:is_a?, true, [::OpenAI::Client])
    fake_client.expect(:chat, fake_chat)

    Braintrust::Contrib::OpenAI::ChatPatcher.perform_patch(target: fake_client)

    fake_singleton_class.verify
    fake_completions.verify
    fake_chat.verify
    fake_client.verify
  end

  def test_chat_patcher_patched_returns_false_when_not_patched
    fake_completions = Class.new

    OpenAI::Resources::Chat.stub_const(:Completions, fake_completions) do
      refute Braintrust::Contrib::OpenAI::ChatPatcher.patched?
    end
  end

  def test_chat_patcher_patched_returns_true_after_patching
    # Use real classes for this test since we're actually including modules
    Braintrust::Contrib::OpenAI::ChatPatcher.perform_patch

    assert Braintrust::Contrib::OpenAI::ChatPatcher.patched?
  end

  # ResponsesPatcher tests

  def test_responses_patcher_applicable_with_responses_method
    assert Braintrust::Contrib::OpenAI::ResponsesPatcher.applicable?
  end

  def test_responses_patcher_includes_correct_module_for_class_level
    skip "Responses API not available" unless OpenAI::Client.instance_methods.include?(:responses)

    fake_responses = Minitest::Mock.new
    fake_responses.expect(:include, true, [Braintrust::Contrib::OpenAI::Instrumentation::Responses])

    OpenAI::Resources.stub_const(:Responses, fake_responses) do
      Braintrust::Contrib::OpenAI::ResponsesPatcher.perform_patch
      fake_responses.verify
    end
  end

  def test_responses_patcher_includes_correct_module_for_instance_level
    skip "Responses API not available" unless OpenAI::Client.instance_methods.include?(:responses)

    fake_singleton_class = Minitest::Mock.new
    fake_singleton_class.expect(:include, true, [Braintrust::Contrib::OpenAI::Instrumentation::Responses])

    fake_responses = Minitest::Mock.new
    fake_responses.expect(:singleton_class, fake_singleton_class)

    fake_client = Minitest::Mock.new
    fake_client.expect(:is_a?, true, [::OpenAI::Client])
    fake_client.expect(:responses, fake_responses)

    Braintrust::Contrib::OpenAI::ResponsesPatcher.perform_patch(target: fake_client)

    fake_singleton_class.verify
    fake_responses.verify
    fake_client.verify
  end

  def test_responses_patcher_patched_returns_false_when_not_patched
    skip "Responses API not available" unless OpenAI::Client.instance_methods.include?(:responses)

    fake_responses = Class.new

    OpenAI::Resources.stub_const(:Responses, fake_responses) do
      refute Braintrust::Contrib::OpenAI::ResponsesPatcher.patched?
    end
  end

  def test_responses_patcher_patched_returns_true_after_patching
    skip "Responses API not available" unless OpenAI::Client.instance_methods.include?(:responses)

    # Use real classes for this test since we're actually including modules
    Braintrust::Contrib::OpenAI::ResponsesPatcher.perform_patch

    assert Braintrust::Contrib::OpenAI::ResponsesPatcher.patched?
  end

  # Integration patch! method tests (these test the Integration layer, not instrumentation)

  def test_integration_patch_applies_all_applicable_patchers
    fake_chat = Minitest::Mock.new
    # ancestors is called twice per patcher: once for fast-path patched? check, once under lock
    2.times { fake_chat.expect(:ancestors, []) }
    fake_chat.expect(:include, true, [Braintrust::Contrib::OpenAI::Instrumentation::Chat::Completions])

    fake_responses = Minitest::Mock.new
    2.times { fake_responses.expect(:ancestors, []) }
    fake_responses.expect(:include, true, [Braintrust::Contrib::OpenAI::Instrumentation::Responses])

    OpenAI::Resources::Chat.stub_const(:Completions, fake_chat) do
      OpenAI::Resources.stub_const(:Responses, fake_responses) do
        result = Braintrust::Contrib::OpenAI::Integration.patch!

        assert result, "patch! should return true when patchers succeed"
        fake_chat.verify
        fake_responses.verify if OpenAI::Client.instance_methods.include?(:responses)
      end
    end
  end

  def test_integration_patch_is_idempotent
    # First patch
    result1 = Braintrust::Contrib::OpenAI::Integration.patch!
    assert result1, "First patch should succeed"

    # Second patch should also succeed (idempotent)
    result2 = Braintrust::Contrib::OpenAI::Integration.patch!
    assert result2, "Second patch should also succeed (idempotent)"
  end
end
