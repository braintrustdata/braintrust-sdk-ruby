# frozen_string_literal: true

require "test_helper"
require "braintrust/trace/auto_instrument"

class Braintrust::Trace::AutoInstrumentTest < Minitest::Test
  def test_libraries_constant_includes_openai_and_anthropic
    # Test that LIBRARIES constant is defined with correct structure
    libraries = Braintrust::Trace::AutoInstrument::LIBRARIES

    assert_includes libraries.keys, :openai
    assert_includes libraries.keys, :anthropic

    # Verify OpenAI config
    assert_equal "OpenAI::Client", libraries[:openai][:class_name]
    assert_equal Braintrust::Trace::OpenAI, libraries[:openai][:wrapper_module]

    # Verify Anthropic config
    assert_equal "Anthropic::Client", libraries[:anthropic][:class_name]
    assert_equal Braintrust::Trace::Anthropic, libraries[:anthropic][:wrapper_module]
  end

  def test_determine_libraries_with_no_filters
    # When enabled: true with no include/exclude, return all libraries
    config = {enabled: true, include: nil, exclude: nil}
    libraries = Braintrust::Trace::AutoInstrument.send(:determine_libraries, config)

    assert_equal [:anthropic, :openai], libraries.sort
  end

  def test_determine_libraries_with_include
    # When include list provided, return only those libraries
    config = {enabled: true, include: [:openai], exclude: nil}
    libraries = Braintrust::Trace::AutoInstrument.send(:determine_libraries, config)

    assert_equal [:openai], libraries
  end

  def test_determine_libraries_with_exclude
    # When exclude list provided, return all except excluded
    config = {enabled: true, include: nil, exclude: [:anthropic]}
    libraries = Braintrust::Trace::AutoInstrument.send(:determine_libraries, config)

    assert_equal [:openai], libraries
  end

  def test_determine_libraries_with_unknown_library_in_include
    # Unknown libraries in include list should be ignored (they won't be in LIBRARIES.keys)
    config = {enabled: true, include: [:openai, :unknown_lib], exclude: nil}
    libraries = Braintrust::Trace::AutoInstrument.send(:determine_libraries, config)

    assert_equal [:openai], libraries
  end

  def test_library_available_detects_missing_library
    # Should return false for a library that doesn't exist
    available = Braintrust::Trace::AutoInstrument.send(:library_available?, "NonExistent::Library")
    assert_equal false, available
  end

  def test_library_available_detects_existing_library
    # Should return true for a library that exists (Minitest is loaded in tests)
    available = Braintrust::Trace::AutoInstrument.send(:library_available?, "Minitest::Test")
    assert_equal true, available
  end

  def test_library_available_with_simple_class
    # Should work with non-namespaced classes too
    available = Braintrust::Trace::AutoInstrument.send(:library_available?, "String")
    assert_equal true, available
  end

  def test_autoinstrument_integration_with_openai
    # Integration test: verify that init with autoinstrument actually instruments OpenAI
    skip "OpenAI gem not available" unless defined?(OpenAI)

    VCR.use_cassette("openai/chat_completions") do
      require "openai"

      # Set up test rig
      rig = setup_otel_test_rig

      # Initialize Braintrust with auto-instrumentation enabled
      state = Braintrust::State.new(
        api_key: ENV["OPENAI_API_KEY"] || "test-key",
        enable_tracing: false,  # We're managing tracing manually with our rig
        autoinstrument: {enabled: true, include: [:openai]}
      )

      # Manually trigger Trace.setup with our test tracer provider
      Braintrust::Trace::AutoInstrument.setup(state.autoinstrument_config, rig.tracer_provider)

      # Create a NEW OpenAI client AFTER auto-instrumentation is set up
      # This should be automatically wrapped
      client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"] || "test-key")

      # Make a request
      response = client.chat.completions.create(
        messages: [{role: "user", content: "Say 'test'"}],
        model: "gpt-4o-mini",
        max_tokens: 10
      )

      refute_nil response

      # Should have a span because of auto-instrumentation
      spans = rig.drain
      assert_equal 1, spans.length
      assert_equal "openai.chat.completions.create", spans.first.name
    end
  end

  def test_autoinstrument_disabled_by_default
    # Integration test: verify that when autoinstrument is NOT enabled, clients are not wrapped
    skip "OpenAI gem not available" unless defined?(OpenAI)

    VCR.use_cassette("openai/chat_completions") do
      require "openai"

      rig = setup_otel_test_rig

      # Initialize with autoinstrument disabled (default)
      state = Braintrust::State.new(
        api_key: ENV["OPENAI_API_KEY"] || "test-key",
        enable_tracing: false
      )

      # Verify default is disabled
      assert_equal({enabled: false}, state.autoinstrument_config)

      # Manually trigger Trace.setup with disabled config
      Braintrust::Trace::AutoInstrument.setup(state.autoinstrument_config, rig.tracer_provider)

      # Create a NEW OpenAI client - should NOT be auto-wrapped
      client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"] || "test-key")

      # Make a request
      response = client.chat.completions.create(
        messages: [{role: "user", content: "Say 'test'"}],
        model: "gpt-4o-mini",
        max_tokens: 10
      )

      refute_nil response

      # Should have NO spans because auto-instrumentation is disabled
      spans = rig.drain
      assert_equal 0, spans.length
    end
  end
end
