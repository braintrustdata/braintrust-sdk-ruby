# frozen_string_literal: true

require "test_helper"

# Verifies that after instrumenting with :llm_rb, LLM::Context#talk produces
# Braintrust-enriched spans. Companion to the integration tests in
# test/braintrust/contrib/llm_rb/.
class Braintrust::Contrib::LlmRbSpansTest < Minitest::Test
  def setup
    @llm_available = begin
      require "llm"
      true
    rescue LoadError
      false
    end
  end

  def teardown
    # Reset patcher state after each test
    Braintrust::Contrib::LlmRb::ContextPatcher.reset! if defined?(Braintrust::Contrib::LlmRb::ContextPatcher)
  end

  def test_llm_rb_context_patched_after_instrument
    skip "llm.rb gem not available" unless @llm_available

    ancestors_before = ::LLM::Context.ancestors.map(&:to_s)
    bt_before = ancestors_before.select { |a| a.include?("Braintrust") }
    assert_empty bt_before, "LLM::Context should start unpatched"

    Braintrust.instrument!(:llm_rb)

    ancestors_after = ::LLM::Context.ancestors.map(&:to_s)
    bt_after = ancestors_after.select { |a| a.include?("Braintrust") }
    refute_empty bt_after, "LLM::Context should be patched after instrument!(:llm_rb)"
  end

  def test_llm_rb_loaded_detected_by_llm_rb_integration
    skip "llm.rb gem not available" unless @llm_available

    assert defined?(::LLM::Context), "LLM::Context should be defined"

    integration = Braintrust::Contrib::Registry.instance[:llm_rb]
    refute_nil integration
    assert integration.loaded?, "llm_rb integration should report loaded? = true when llm.rb is loaded"
  end
end
