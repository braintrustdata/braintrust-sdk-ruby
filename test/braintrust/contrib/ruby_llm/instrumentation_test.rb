# frozen_string_literal: true

require "test_helper"
require_relative "integration_helper"

# Explicitly load the patcher (lazy-loaded by integration)
require "braintrust/contrib/ruby_llm/patcher"

# Tests for instance-level instrumentation behavior
class Braintrust::Contrib::RubyLLM::InstrumentationTest < Minitest::Test
  include Braintrust::Contrib::RubyLLM::IntegrationHelper

  def setup
    skip_unless_ruby_llm!
  end

  # --- Instance-level instrumentation ---

  def test_instance_instrumentation_only_patches_target_chat
    # Skip if class-level patching already occurred from another test
    skip "class already patched by another test" if Braintrust::Contrib::RubyLLM::ChatPatcher.patched?

    rig = setup_otel_test_rig

    # Configure RubyLLM with a test key
    RubyLLM.configure do |config|
      config.openai_api_key = "test-api-key"
    end

    # Create two chat instances BEFORE any patching
    chat_traced = RubyLLM::Chat.new(model: "gpt-4o-mini")
    chat_untraced = RubyLLM::Chat.new(model: "gpt-4o-mini")

    # Verify neither client is patched initially
    refute Braintrust::Contrib::RubyLLM::ChatPatcher.patched?(target: chat_traced),
      "chat_traced should not be patched initially"
    refute Braintrust::Contrib::RubyLLM::ChatPatcher.patched?(target: chat_untraced),
      "chat_untraced should not be patched initially"

    # Verify class is not patched
    refute Braintrust::Contrib::RubyLLM::ChatPatcher.patched?,
      "class should not be patched initially"

    # Instrument only one chat (instance-level)
    Braintrust.instrument!(:ruby_llm, target: chat_traced, tracer_provider: rig.tracer_provider)

    # Only the traced chat should be patched
    assert Braintrust::Contrib::RubyLLM::ChatPatcher.patched?(target: chat_traced),
      "chat_traced should be patched after instrument!"
    refute Braintrust::Contrib::RubyLLM::ChatPatcher.patched?(target: chat_untraced),
      "chat_untraced should NOT be patched after instrument!"

    # Class itself should NOT be patched (only the instance)
    refute Braintrust::Contrib::RubyLLM::ChatPatcher.patched?,
      "class should NOT be patched when using instance-level instrumentation"
  end
end
