# frozen_string_literal: true

require "test_helper"
require_relative "integration_helper"

# Explicitly load the patcher (lazy-loaded by integration)
require "braintrust/contrib/anthropic/patcher"

class Braintrust::Contrib::Anthropic::MessagesPatcherTest < Minitest::Test
  include Braintrust::Contrib::Anthropic::IntegrationHelper

  def setup
    skip_unless_anthropic!
  end

  # --- .applicable? ---

  def test_applicable_returns_true_when_anthropic_client_defined
    assert Braintrust::Contrib::Anthropic::MessagesPatcher.applicable?
  end

  # --- .patched? ---

  def test_patched_returns_false_when_not_patched
    fake_messages_class = Class.new

    ::Anthropic::Resources.stub_const(:Messages, fake_messages_class) do
      refute Braintrust::Contrib::Anthropic::MessagesPatcher.patched?
    end
  end

  def test_patched_returns_true_when_module_included
    fake_messages_class = Class.new do
      include Braintrust::Contrib::Anthropic::Instrumentation::Messages
    end

    ::Anthropic::Resources.stub_const(:Messages, fake_messages_class) do
      assert Braintrust::Contrib::Anthropic::MessagesPatcher.patched?
    end
  end

  def test_patched_returns_false_for_unpatched_instance
    fake_singleton = Class.new

    mock_chain(:messages, :singleton_class, returns: fake_singleton) do |client|
      refute Braintrust::Contrib::Anthropic::MessagesPatcher.patched?(target: client)
    end
  end

  def test_patched_returns_true_for_patched_instance
    fake_singleton = Class.new do
      include Braintrust::Contrib::Anthropic::Instrumentation::Messages
    end

    mock_chain(:messages, :singleton_class, returns: fake_singleton) do |client|
      assert Braintrust::Contrib::Anthropic::MessagesPatcher.patched?(target: client)
    end
  end

  # --- .perform_patch ---

  def test_perform_patch_includes_module_for_class_level
    fake_messages_class = Minitest::Mock.new
    fake_messages_class.expect(:include, true, [Braintrust::Contrib::Anthropic::Instrumentation::Messages])

    ::Anthropic::Resources.stub_const(:Messages, fake_messages_class) do
      Braintrust::Contrib::Anthropic::MessagesPatcher.perform_patch
      fake_messages_class.verify
    end
  end

  def test_perform_patch_includes_module_for_instance_level
    terminal = Minitest::Mock.new
    terminal.expect(:include, true, [Braintrust::Contrib::Anthropic::Instrumentation::Messages])

    mock_chain(:messages, :singleton_class, returns: terminal) do |client|
      client.expect(:is_a?, true, [::Anthropic::Client])
      Braintrust::Contrib::Anthropic::MessagesPatcher.perform_patch(target: client)
    end
    terminal.verify
  end

  def test_perform_patch_raises_for_invalid_target
    fake_client = Minitest::Mock.new
    fake_client.expect(:is_a?, false, [::Anthropic::Client])

    assert_raises(ArgumentError) do
      Braintrust::Contrib::Anthropic::MessagesPatcher.perform_patch(target: fake_client)
    end

    fake_client.verify
  end
end

class Braintrust::Contrib::Anthropic::BetaMessagesPatcherTest < Minitest::Test
  include Braintrust::Contrib::Anthropic::IntegrationHelper

  def setup
    skip_unless_anthropic!
    skip_unless_beta_messages!
  end

  # --- .applicable? ---

  def test_applicable_returns_true_when_beta_messages_defined
    assert Braintrust::Contrib::Anthropic::BetaMessagesPatcher.applicable?
  end

  # --- .patched? ---

  def test_patched_returns_false_when_not_patched
    fake_beta_messages_class = Class.new

    ::Anthropic::Resources::Beta.stub_const(:Messages, fake_beta_messages_class) do
      refute Braintrust::Contrib::Anthropic::BetaMessagesPatcher.patched?
    end
  end

  def test_patched_returns_true_when_module_included
    fake_beta_messages_class = Class.new do
      include Braintrust::Contrib::Anthropic::Instrumentation::BetaMessages
    end

    ::Anthropic::Resources::Beta.stub_const(:Messages, fake_beta_messages_class) do
      assert Braintrust::Contrib::Anthropic::BetaMessagesPatcher.patched?
    end
  end

  def test_patched_returns_false_for_unpatched_instance
    fake_singleton = Class.new

    mock_beta_chain(:beta, :messages, :singleton_class, returns: fake_singleton) do |client|
      refute Braintrust::Contrib::Anthropic::BetaMessagesPatcher.patched?(target: client)
    end
  end

  def test_patched_returns_true_for_patched_instance
    fake_singleton = Class.new do
      include Braintrust::Contrib::Anthropic::Instrumentation::BetaMessages
    end

    mock_beta_chain(:beta, :messages, :singleton_class, returns: fake_singleton) do |client|
      assert Braintrust::Contrib::Anthropic::BetaMessagesPatcher.patched?(target: client)
    end
  end

  # --- .perform_patch ---

  def test_perform_patch_includes_module_for_class_level
    fake_beta_messages_class = Minitest::Mock.new
    fake_beta_messages_class.expect(:include, true, [Braintrust::Contrib::Anthropic::Instrumentation::BetaMessages])

    ::Anthropic::Resources::Beta.stub_const(:Messages, fake_beta_messages_class) do
      Braintrust::Contrib::Anthropic::BetaMessagesPatcher.perform_patch
      fake_beta_messages_class.verify
    end
  end

  def test_perform_patch_includes_module_for_instance_level
    terminal = Minitest::Mock.new
    terminal.expect(:include, true, [Braintrust::Contrib::Anthropic::Instrumentation::BetaMessages])

    mock_beta_chain(:beta, :messages, :singleton_class, returns: terminal) do |client|
      client.expect(:is_a?, true, [::Anthropic::Client])
      Braintrust::Contrib::Anthropic::BetaMessagesPatcher.perform_patch(target: client)
    end
    terminal.verify
  end

  def test_perform_patch_raises_for_invalid_target
    fake_client = Minitest::Mock.new
    fake_client.expect(:is_a?, false, [::Anthropic::Client])

    assert_raises(ArgumentError) do
      Braintrust::Contrib::Anthropic::BetaMessagesPatcher.perform_patch(target: fake_client)
    end

    fake_client.verify
  end

  private

  # Helper to mock client.beta.messages.singleton_class chain
  def mock_beta_chain(*methods, returns:)
    current = returns
    mocks = []

    methods.reverse_each do |method|
      mock = Minitest::Mock.new
      mock.expect(method, current)
      mocks.unshift(mock)
      current = mock
    end

    yield mocks.first

    mocks.each(&:verify)
  end
end
