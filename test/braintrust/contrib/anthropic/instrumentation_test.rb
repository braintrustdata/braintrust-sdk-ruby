# frozen_string_literal: true

require "test_helper"
require_relative "integration_helper"

# Explicitly load the patcher (lazy-loaded by integration)
require "braintrust/contrib/anthropic/patcher"
require "braintrust/contrib/anthropic/deprecated"

# Tests for instance-level instrumentation behavior and backward compatibility
class Braintrust::Contrib::Anthropic::InstrumentationTest < Minitest::Test
  include Braintrust::Contrib::Anthropic::IntegrationHelper

  def setup
    skip_unless_anthropic!
  end

  # --- Instance-level instrumentation ---

  def test_instance_instrumentation_only_patches_target_client
    # Skip if class-level patching already occurred from another test
    skip "class already patched by another test" if Braintrust::Contrib::Anthropic::MessagesPatcher.patched?

    rig = setup_otel_test_rig

    # Create two client instances BEFORE any patching
    client_traced = Anthropic::Client.new(api_key: "test-api-key")
    client_untraced = Anthropic::Client.new(api_key: "test-api-key")

    # Verify neither client is patched initially
    refute Braintrust::Contrib::Anthropic::MessagesPatcher.patched?(target: client_traced),
      "client_traced should not be patched initially"
    refute Braintrust::Contrib::Anthropic::MessagesPatcher.patched?(target: client_untraced),
      "client_untraced should not be patched initially"

    # Verify class is not patched
    refute Braintrust::Contrib::Anthropic::MessagesPatcher.patched?,
      "class should not be patched initially"

    # Instrument only one client (instance-level)
    Braintrust.instrument!(:anthropic, target: client_traced, tracer_provider: rig.tracer_provider)

    # Only the traced client should be patched
    assert Braintrust::Contrib::Anthropic::MessagesPatcher.patched?(target: client_traced),
      "client_traced should be patched after instrument!"
    refute Braintrust::Contrib::Anthropic::MessagesPatcher.patched?(target: client_untraced),
      "client_untraced should NOT be patched after instrument!"

    # Class itself should NOT be patched (only the instance)
    refute Braintrust::Contrib::Anthropic::MessagesPatcher.patched?,
      "class should NOT be patched when using instance-level instrumentation"
  end

  # --- Backward compatibility: wrap() vs instrument!() ---

  def test_wrap_and_instrument_produce_identical_spans
    VCR.use_cassette("anthropic/basic_message", allow_playback_repeats: true) do
      # Test with old wrap() API
      rig_wrap = setup_otel_test_rig
      client_wrap = Anthropic::Client.new(api_key: get_anthropic_key)
      suppress_logs { Braintrust::Trace::Anthropic.wrap(client_wrap, tracer_provider: rig_wrap.tracer_provider) }

      client_wrap.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 10,
        messages: [{role: "user", content: "Say 'test'"}]
      )
      span_wrap = rig_wrap.drain_one

      # Test with new instrument!() API
      rig_instrument = setup_otel_test_rig
      client_instrument = Anthropic::Client.new(api_key: get_anthropic_key)
      Braintrust.instrument!(:anthropic, target: client_instrument, tracer_provider: rig_instrument.tracer_provider)

      client_instrument.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 10,
        messages: [{role: "user", content: "Say 'test'"}]
      )
      span_instrument = rig_instrument.drain_one

      # Both spans should have identical structure
      assert_equal span_wrap.name, span_instrument.name,
        "span names should match"
      assert_equal span_wrap.attributes["braintrust.input_json"],
        span_instrument.attributes["braintrust.input_json"],
        "input attributes should match"
      assert_equal span_wrap.attributes["braintrust.output_json"],
        span_instrument.attributes["braintrust.output_json"],
        "output attributes should match"

      # Compare token metrics (timing metrics like time_to_first_token may vary between calls)
      metrics_wrap = JSON.parse(span_wrap.attributes["braintrust.metrics"])
      metrics_instrument = JSON.parse(span_instrument.attributes["braintrust.metrics"])
      %w[prompt_tokens completion_tokens tokens].each do |key|
        assert_equal metrics_wrap[key], metrics_instrument[key],
          "metrics #{key} should match"
      end

      # Both should have time_to_first_token (but values may differ)
      assert metrics_wrap.key?("time_to_first_token"), "wrap metrics should have time_to_first_token"
      assert metrics_instrument.key?("time_to_first_token"), "instrument metrics should have time_to_first_token"

      # Metadata should have same keys (values may differ slightly for timestamps)
      metadata_wrap = JSON.parse(span_wrap.attributes["braintrust.metadata"])
      metadata_instrument = JSON.parse(span_instrument.attributes["braintrust.metadata"])
      assert_equal metadata_wrap.keys.sort, metadata_instrument.keys.sort,
        "metadata keys should match"
    end
  end
end
