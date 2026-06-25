# frozen_string_literal: true

require "test_helper"

# Historical note: This file previously tested the GAP described in issue #140
# where the llm.rb gem had no Braintrust integration.
#
# The integration has since been implemented as :llm_rb. These tests now verify
# that the integration is registered and working correctly at the registry level.
class Braintrust::Contrib::LlmRbRegistryTest < Minitest::Test
  def setup
    @registry = Braintrust::Contrib::Registry.instance
  end

  def test_integration_registered_for_llm_rb
    assert_equal :llm_rb, @registry[:llm_rb]&.integration_name,
      "Expected :llm_rb integration to be registered"
  end

  def test_five_integrations_registered
    names = @registry.all.map(&:integration_name)
    assert_equal [:openai, :ruby_openai, :ruby_llm, :anthropic, :llm_rb], names,
      "Expected exactly 5 integrations: openai, ruby_openai, ruby_llm, anthropic, llm_rb"
  end

  def test_require_path_llm_detected
    matches = @registry.integrations_for_require_path("llm")
    names = matches.map(&:integration_name)
    assert_includes names, :llm_rb,
      "Expected :llm_rb to be detected when require path 'llm' is seen"
  end

  def test_instrument_llm_rb_returns_truthy_when_loaded
    skip "llm.rb gem not available" unless Gem.loaded_specs["llm.rb"]
    require "llm" unless defined?(::LLM)

    result = Braintrust::Contrib.instrument!(:llm_rb)
    assert result, "Expected instrument!(:llm_rb) to return truthy when gem is loaded"
  end
end
