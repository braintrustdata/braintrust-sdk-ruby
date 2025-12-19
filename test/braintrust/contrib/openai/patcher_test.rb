# frozen_string_literal: true

require "test_helper"

# Explicitly load the patcher (lazy-loaded by integration)
require "braintrust/contrib/openai/patcher"

class Braintrust::Contrib::OpenAI::ChatPatcherTest < Minitest::Test
  def setup
    skip "OpenAI gem not available" unless defined?(OpenAI)

    if Gem.loaded_specs["ruby-openai"]
      skip "openai gem not available (found ruby-openai gem instead)"
    elsif !Gem.loaded_specs["openai"]
      skip "Could not determine which OpenAI gem is loaded"
    end
  end

  # --- .applicable? ---

  def test_applicable_returns_true_when_openai_client_defined
    assert Braintrust::Contrib::OpenAI::ChatPatcher.applicable?
  end

  # --- .patched? ---

  def test_patched_returns_false_when_module_not_included
    fake_completions = Class.new

    OpenAI::Resources::Chat.stub_const(:Completions, fake_completions) do
      refute Braintrust::Contrib::OpenAI::ChatPatcher.patched?
    end
  end

  def test_patched_returns_true_when_module_included
    fake_completions = Class.new do
      include Braintrust::Contrib::OpenAI::Instrumentation::Chat::Completions
    end

    OpenAI::Resources::Chat.stub_const(:Completions, fake_completions) do
      assert Braintrust::Contrib::OpenAI::ChatPatcher.patched?
    end
  end

  def test_patched_returns_false_for_unpatched_instance
    fake_singleton = Class.new

    mock_chain(:chat, :completions, :singleton_class, returns: fake_singleton) do |client|
      refute Braintrust::Contrib::OpenAI::ChatPatcher.patched?(target: client)
    end
  end

  def test_patched_returns_true_for_patched_instance
    fake_singleton = Class.new do
      include Braintrust::Contrib::OpenAI::Instrumentation::Chat::Completions
    end

    mock_chain(:chat, :completions, :singleton_class, returns: fake_singleton) do |client|
      assert Braintrust::Contrib::OpenAI::ChatPatcher.patched?(target: client)
    end
  end

  # --- .perform_patch ---

  def test_perform_patch_includes_module_for_class_level
    fake_completions = Minitest::Mock.new
    fake_completions.expect(:include, true, [Braintrust::Contrib::OpenAI::Instrumentation::Chat::Completions])

    OpenAI::Resources::Chat.stub_const(:Completions, fake_completions) do
      Braintrust::Contrib::OpenAI::ChatPatcher.perform_patch
      fake_completions.verify
    end
  end

  def test_perform_patch_includes_module_for_instance_level
    terminal = Minitest::Mock.new
    terminal.expect(:include, true, [Braintrust::Contrib::OpenAI::Instrumentation::Chat::Completions])

    mock_chain(:chat, :completions, :singleton_class, returns: terminal) do |client|
      client.expect(:is_a?, true, [::OpenAI::Client])
      Braintrust::Contrib::OpenAI::ChatPatcher.perform_patch(target: client)
    end
    terminal.verify
  end

  def test_perform_patch_raises_for_invalid_target
    fake_client = Minitest::Mock.new
    fake_client.expect(:is_a?, false, [::OpenAI::Client])

    assert_raises(ArgumentError) do
      Braintrust::Contrib::OpenAI::ChatPatcher.perform_patch(target: fake_client)
    end

    fake_client.verify
  end
end

class Braintrust::Contrib::OpenAI::ResponsesPatcherTest < Minitest::Test
  def setup
    skip "OpenAI gem not available" unless defined?(OpenAI)

    if Gem.loaded_specs["ruby-openai"]
      skip "openai gem not available (found ruby-openai gem instead)"
    elsif !Gem.loaded_specs["openai"]
      skip "Could not determine which OpenAI gem is loaded"
    end

    skip "Responses API not available" unless OpenAI::Client.instance_methods.include?(:responses)
  end

  # --- .applicable? ---

  def test_applicable_returns_true_when_responses_method_exists
    assert Braintrust::Contrib::OpenAI::ResponsesPatcher.applicable?
  end

  # --- .patched? ---

  def test_patched_returns_false_when_module_not_included
    fake_responses = Class.new

    OpenAI::Resources.stub_const(:Responses, fake_responses) do
      refute Braintrust::Contrib::OpenAI::ResponsesPatcher.patched?
    end
  end

  def test_patched_returns_true_when_module_included
    fake_responses = Class.new do
      include Braintrust::Contrib::OpenAI::Instrumentation::Responses
    end

    OpenAI::Resources.stub_const(:Responses, fake_responses) do
      assert Braintrust::Contrib::OpenAI::ResponsesPatcher.patched?
    end
  end

  def test_patched_returns_false_for_unpatched_instance
    fake_singleton = Class.new

    mock_chain(:responses, :singleton_class, returns: fake_singleton) do |client|
      refute Braintrust::Contrib::OpenAI::ResponsesPatcher.patched?(target: client)
    end
  end

  def test_patched_returns_true_for_patched_instance
    fake_singleton = Class.new do
      include Braintrust::Contrib::OpenAI::Instrumentation::Responses
    end

    mock_chain(:responses, :singleton_class, returns: fake_singleton) do |client|
      assert Braintrust::Contrib::OpenAI::ResponsesPatcher.patched?(target: client)
    end
  end

  # --- .perform_patch ---

  def test_perform_patch_includes_module_for_class_level
    fake_responses = Minitest::Mock.new
    fake_responses.expect(:include, true, [Braintrust::Contrib::OpenAI::Instrumentation::Responses])

    OpenAI::Resources.stub_const(:Responses, fake_responses) do
      Braintrust::Contrib::OpenAI::ResponsesPatcher.perform_patch
      fake_responses.verify
    end
  end

  def test_perform_patch_includes_module_for_instance_level
    terminal = Minitest::Mock.new
    terminal.expect(:include, true, [Braintrust::Contrib::OpenAI::Instrumentation::Responses])

    mock_chain(:responses, :singleton_class, returns: terminal) do |client|
      client.expect(:is_a?, true, [::OpenAI::Client])
      Braintrust::Contrib::OpenAI::ResponsesPatcher.perform_patch(target: client)
    end
    terminal.verify
  end

  def test_perform_patch_raises_for_invalid_target
    fake_client = Minitest::Mock.new
    fake_client.expect(:is_a?, false, [::OpenAI::Client])

    assert_raises(ArgumentError) do
      Braintrust::Contrib::OpenAI::ResponsesPatcher.perform_patch(target: fake_client)
    end

    fake_client.verify
  end
end
