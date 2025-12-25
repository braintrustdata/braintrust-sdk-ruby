# frozen_string_literal: true

require "test_helper"

# Explicitly load the patcher (lazy-loaded by integration)
require "braintrust/contrib/ruby_openai/patcher"

# Tests for instance-level instrumentation behavior
class Braintrust::Contrib::RubyOpenAI::InstrumentationTest < Minitest::Test
  def setup
    # Skip if official openai gem is loaded (has OpenAI::Internal)
    if defined?(::OpenAI::Internal)
      skip "ruby-openai gem not available (found official openai gem instead)"
    elsif !Gem.loaded_specs["ruby-openai"]
      skip "ruby-openai gem not available"
    end

    require "openai" unless defined?(OpenAI)
  end

  # --- Instance-level instrumentation ---

  def test_instance_instrumentation_only_patches_target_client
    # Skip if class-level patching already occurred from another test
    skip "class already patched by another test" if Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?

    rig = setup_otel_test_rig

    # Create two clients BEFORE any patching
    client_traced = OpenAI::Client.new(access_token: "test-key")
    client_untraced = OpenAI::Client.new(access_token: "test-key")

    # Verify neither client is patched initially
    refute Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?(target: client_traced),
      "client_traced should not be patched initially"
    refute Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?(target: client_untraced),
      "client_untraced should not be patched initially"

    # Verify class is not patched
    refute Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?,
      "class should not be patched initially"

    # Instrument only one client (instance-level)
    Braintrust.instrument!(:ruby_openai, target: client_traced, tracer_provider: rig.tracer_provider)

    # Only the traced client should be patched
    assert Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?(target: client_traced),
      "client_traced should be patched after instrument!"
    refute Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?(target: client_untraced),
      "client_untraced should NOT be patched after instrument!"

    # Class itself should NOT be patched (only the instance)
    refute Braintrust::Contrib::RubyOpenAI::ChatPatcher.patched?,
      "class should NOT be patched when using instance-level instrumentation"
  end
end
