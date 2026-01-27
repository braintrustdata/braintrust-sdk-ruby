# frozen_string_literal: true

require "test_helper"
require_relative "integration_helper"

# Explicitly load the patcher (lazy-loaded by integration)
require "braintrust/contrib/ruby_openai/patcher"

class Braintrust::Contrib::RubyOpenAI::ChatPatcherTest < Minitest::Test
  include Braintrust::Contrib::RubyOpenAI::IntegrationHelper

  def setup
    skip_unless_ruby_openai!
  end

  # --- .applicable? ---

  def test_applicable_returns_true_when_openai_client_defined
    assert Braintrust::Contrib::RubyOpenAI::ChatPatcher.applicable?
  end

  # --- .patched? ---

  def test_patched_returns_false_when_not_patched
    fake_client_class = Class.new

    OpenAI.stub_const(:Client, fake_client_class) do
      refute Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?
    end
  end

  def test_patched_returns_true_when_module_included
    fake_client_class = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Chat
    end

    OpenAI.stub_const(:Client, fake_client_class) do
      assert Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?
    end
  end

  def test_patched_returns_false_for_unpatched_instance
    fake_singleton = Class.new

    mock_chain(:singleton_class, returns: fake_singleton) do |client|
      refute Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?(target: client)
    end
  end

  def test_patched_returns_true_for_patched_instance
    fake_singleton = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Chat
    end

    mock_chain(:singleton_class, returns: fake_singleton) do |client|
      assert Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?(target: client)
    end
  end

  # --- .perform_patch ---

  def test_perform_patch_includes_module_for_class_level
    fake_client_class = Minitest::Mock.new
    fake_client_class.expect(:include, true, [Braintrust::Contrib::RubyOpenAI::Instrumentation::Chat])

    OpenAI.stub_const(:Client, fake_client_class) do
      Braintrust::Contrib::RubyOpenAI::ChatPatcher.perform_patch
      fake_client_class.verify
    end
  end

  def test_perform_patch_includes_module_for_instance_level
    terminal = Minitest::Mock.new
    terminal.expect(:include, true, [Braintrust::Contrib::RubyOpenAI::Instrumentation::Chat])

    mock_chain(:singleton_class, returns: terminal) do |client|
      client.expect(:is_a?, true, [::OpenAI::Client])
      Braintrust::Contrib::RubyOpenAI::ChatPatcher.perform_patch(target: client)
    end
    terminal.verify
  end

  def test_perform_patch_raises_for_invalid_target
    fake_client = Minitest::Mock.new
    fake_client.expect(:is_a?, false, [::OpenAI::Client])

    assert_raises(ArgumentError) do
      Braintrust::Contrib::RubyOpenAI::ChatPatcher.perform_patch(target: fake_client)
    end

    fake_client.verify
  end
end

class Braintrust::Contrib::RubyOpenAI::ResponsesPatcherTest < Minitest::Test
  include Braintrust::Contrib::RubyOpenAI::IntegrationHelper

  def setup
    skip_unless_ruby_openai!
  end

  # --- .applicable? ---

  def test_applicable_returns_true_when_responses_method_exists
    skip "Responses API not available" unless OpenAI::Client.method_defined?(:responses)

    assert Braintrust::Contrib::RubyOpenAI::ResponsesPatcher.applicable?
  end

  def test_applicable_returns_false_when_responses_method_missing
    fake_client_class = Class.new

    OpenAI.stub_const(:Client, fake_client_class) do
      refute Braintrust::Contrib::RubyOpenAI::ResponsesPatcher.applicable?
    end
  end

  # --- .patched? ---

  def test_patched_returns_false_when_not_patched
    skip "Responses API not available" unless OpenAI::Client.method_defined?(:responses)
    skip "OpenAI::Responses not defined" unless defined?(::OpenAI::Responses)

    fake_responses_class = Class.new

    OpenAI.stub_const(:Responses, fake_responses_class) do
      refute Braintrust::Contrib::RubyOpenAI::ResponsesPatcher.patched?
    end
  end

  def test_patched_returns_true_when_module_included
    skip "Responses API not available" unless OpenAI::Client.method_defined?(:responses)
    skip "OpenAI::Responses not defined" unless defined?(::OpenAI::Responses)

    fake_responses_class = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Responses
    end

    OpenAI.stub_const(:Responses, fake_responses_class) do
      assert Braintrust::Contrib::RubyOpenAI::ResponsesPatcher.patched?
    end
  end

  def test_patched_returns_false_for_unpatched_instance
    skip "Responses API not available" unless OpenAI::Client.method_defined?(:responses)

    fake_singleton = Class.new

    mock_chain(:responses, :singleton_class, returns: fake_singleton) do |client|
      refute Braintrust::Contrib::RubyOpenAI::ResponsesPatcher.patched?(target: client)
    end
  end

  def test_patched_returns_true_for_patched_instance
    skip "Responses API not available" unless OpenAI::Client.method_defined?(:responses)

    fake_singleton = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Responses
    end

    mock_chain(:responses, :singleton_class, returns: fake_singleton) do |client|
      assert Braintrust::Contrib::RubyOpenAI::ResponsesPatcher.patched?(target: client)
    end
  end

  # --- .perform_patch ---

  def test_perform_patch_includes_module_for_class_level
    skip "Responses API not available" unless OpenAI::Client.method_defined?(:responses)
    skip "OpenAI::Responses not defined" unless defined?(::OpenAI::Responses)

    fake_responses_class = Minitest::Mock.new
    fake_responses_class.expect(:include, true, [Braintrust::Contrib::RubyOpenAI::Instrumentation::Responses])

    OpenAI.stub_const(:Responses, fake_responses_class) do
      Braintrust::Contrib::RubyOpenAI::ResponsesPatcher.perform_patch
      fake_responses_class.verify
    end
  end

  def test_perform_patch_includes_module_for_instance_level
    skip "Responses API not available" unless OpenAI::Client.method_defined?(:responses)

    terminal = Minitest::Mock.new
    terminal.expect(:include, true, [Braintrust::Contrib::RubyOpenAI::Instrumentation::Responses])

    mock_chain(:responses, :singleton_class, returns: terminal) do |client|
      client.expect(:is_a?, true, [::OpenAI::Client])
      Braintrust::Contrib::RubyOpenAI::ResponsesPatcher.perform_patch(target: client)
    end
    terminal.verify
  end

  def test_perform_patch_raises_for_invalid_target
    skip "Responses API not available" unless OpenAI::Client.method_defined?(:responses)

    fake_client = Minitest::Mock.new
    fake_client.expect(:is_a?, false, [::OpenAI::Client])

    assert_raises(ArgumentError) do
      Braintrust::Contrib::RubyOpenAI::ResponsesPatcher.perform_patch(target: fake_client)
    end

    fake_client.verify
  end
end

class Braintrust::Contrib::RubyOpenAI::ModerationsPatcherTest < Minitest::Test
  include Braintrust::Contrib::RubyOpenAI::IntegrationHelper

  def setup
    skip_unless_ruby_openai!
  end

  # --- .applicable? ---

  def test_applicable_returns_true_when_moderations_method_exists
    skip "Moderations API not available" unless OpenAI::Client.method_defined?(:moderations)

    assert Braintrust::Contrib::RubyOpenAI::ModerationsPatcher.applicable?
  end

  def test_applicable_returns_false_when_moderations_method_missing
    fake_client_class = Class.new

    OpenAI.stub_const(:Client, fake_client_class) do
      refute Braintrust::Contrib::RubyOpenAI::ModerationsPatcher.applicable?
    end
  end

  # --- .patched? ---

  def test_patched_returns_false_when_not_patched
    fake_client_class = Class.new

    OpenAI.stub_const(:Client, fake_client_class) do
      refute Braintrust::Contrib::RubyOpenAI::ModerationsPatcher.patched?
    end
  end

  def test_patched_returns_true_when_module_included
    fake_client_class = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Moderations
    end

    OpenAI.stub_const(:Client, fake_client_class) do
      assert Braintrust::Contrib::RubyOpenAI::ModerationsPatcher.patched?
    end
  end

  def test_patched_returns_false_for_unpatched_instance
    fake_singleton = Class.new

    mock_chain(:singleton_class, returns: fake_singleton) do |client|
      refute Braintrust::Contrib::RubyOpenAI::ModerationsPatcher.patched?(target: client)
    end
  end

  def test_patched_returns_true_for_patched_instance
    fake_singleton = Class.new do
      include Braintrust::Contrib::RubyOpenAI::Instrumentation::Moderations
    end

    mock_chain(:singleton_class, returns: fake_singleton) do |client|
      assert Braintrust::Contrib::RubyOpenAI::ModerationsPatcher.patched?(target: client)
    end
  end

  # --- .perform_patch ---

  def test_perform_patch_includes_module_for_class_level
    fake_client_class = Minitest::Mock.new
    fake_client_class.expect(:method_defined?, true, [:moderations])
    fake_client_class.expect(:include, true, [Braintrust::Contrib::RubyOpenAI::Instrumentation::Moderations])

    OpenAI.stub_const(:Client, fake_client_class) do
      Braintrust::Contrib::RubyOpenAI::ModerationsPatcher.perform_patch
      fake_client_class.verify
    end
  end

  def test_perform_patch_includes_module_for_instance_level
    terminal = Minitest::Mock.new
    terminal.expect(:include, true, [Braintrust::Contrib::RubyOpenAI::Instrumentation::Moderations])

    mock_chain(:singleton_class, returns: terminal) do |client|
      client.expect(:is_a?, true, [::OpenAI::Client])
      Braintrust::Contrib::RubyOpenAI::ModerationsPatcher.perform_patch(target: client)
    end
    terminal.verify
  end

  def test_perform_patch_raises_for_invalid_target
    fake_client = Minitest::Mock.new
    fake_client.expect(:is_a?, false, [::OpenAI::Client])

    assert_raises(ArgumentError) do
      Braintrust::Contrib::RubyOpenAI::ModerationsPatcher.perform_patch(target: fake_client)
    end

    fake_client.verify
  end
end
