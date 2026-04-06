# frozen_string_literal: true

require "test_helper"
require_relative "integration_helper"

class Braintrust::Contrib::LlmRb::IntegrationTest < Minitest::Test
  include Braintrust::Contrib::LlmRb::IntegrationHelper

  def test_integration_name
    assert_equal :llm_rb, Braintrust::Contrib::LlmRb::Integration.integration_name
  end

  def test_gem_names
    assert_equal ["llm.rb"], Braintrust::Contrib::LlmRb::Integration.gem_names
  end

  def test_require_paths
    assert_equal ["llm"], Braintrust::Contrib::LlmRb::Integration.require_paths
  end

  def test_minimum_version
    assert_equal "4.11.0", Braintrust::Contrib::LlmRb::Integration.minimum_version
  end

  def test_loaded_returns_true_when_llm_context_defined
    skip_unless_llm_rb!
    assert Braintrust::Contrib::LlmRb::Integration.loaded?
  end

  def test_loaded_returns_false_when_llm_context_not_defined
    # Simulate unloaded state
    was_defined = defined?(::LLM::Context)
    if was_defined
      skip "Cannot undefine LLM::Context in this test environment"
    end
    refute Braintrust::Contrib::LlmRb::Integration.loaded?
  end

  def test_integration_registered_in_registry
    registry = Braintrust::Contrib::Registry.instance
    integration = registry[:llm_rb]
    refute_nil integration, "Expected :llm_rb integration to be registered"
    assert_equal :llm_rb, integration.integration_name
  end

  def test_five_integrations_now_registered
    names = Braintrust::Contrib::Registry.instance.all.map(&:integration_name)
    assert_includes names, :llm_rb, "Expected :llm_rb to be in registry"
    assert_includes names, :openai
    assert_includes names, :anthropic
    assert_includes names, :ruby_llm
    assert_includes names, :ruby_openai
  end

  def test_require_path_llm_detected
    skip_unless_llm_rb!
    registry = Braintrust::Contrib::Registry.instance
    matches = registry.integrations_for_require_path("llm")
    assert_includes matches.map(&:integration_name), :llm_rb
  end
end
