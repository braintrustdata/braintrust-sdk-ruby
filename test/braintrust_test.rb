# frozen_string_literal: true

require "test_helper"

class BraintrustTest < Minitest::Test
  def setup
    # Save original env var
    @original_api_key = ENV["BRAINTRUST_API_KEY"]

    # Reset global state before each test
    Braintrust::State.instance_variable_set(:@global_state, nil)

    # Reset global tracer provider to default proxy
    OpenTelemetry.tracer_provider = OpenTelemetry::Internal::ProxyTracerProvider.new
  end

  def teardown
    # Reset global state after each test
    Braintrust::State.instance_variable_set(:@global_state, nil)

    # Reset global tracer provider to default proxy
    OpenTelemetry.tracer_provider = OpenTelemetry::Internal::ProxyTracerProvider.new

    # Restore original env var
    if @original_api_key
      ENV["BRAINTRUST_API_KEY"] = @original_api_key
    else
      ENV.delete("BRAINTRUST_API_KEY")
    end
  end

  def test_init_sets_global_state_by_default
    ENV["BRAINTRUST_API_KEY"] = "test-key"

    state = Braintrust.init

    assert_same state, Braintrust.current_state
    assert_equal "test-key", state.api_key
  end

  def test_init_with_set_global_false_returns_state
    ENV["BRAINTRUST_API_KEY"] = "test-key"

    # Ensure global state is clean before test
    Braintrust::State.instance_variable_set(:@global_state, nil)

    state = Braintrust.init(set_global: false)

    assert_equal "test-key", state.api_key
    assert_nil Braintrust.current_state
  end

  def test_init_merges_options_with_env
    ENV["BRAINTRUST_API_KEY"] = "env-key"

    state = Braintrust.init(set_global: false, api_key: "explicit-key", default_parent: "project_name:my-project")

    assert_equal "explicit-key", state.api_key
    assert_equal "project_name:my-project", state.default_parent
  end

  def test_init_with_tracing_true_creates_tracer_provider
    # Verify we start with the default proxy provider
    assert_instance_of OpenTelemetry::Internal::ProxyTracerProvider, OpenTelemetry.tracer_provider

    Braintrust.init(set_global: false, api_key: "test-key", tracing: true)

    # Should have created and set a real TracerProvider
    assert_instance_of OpenTelemetry::SDK::Trace::TracerProvider, OpenTelemetry.tracer_provider
  end

  def test_init_with_tracing_true_uses_existing_provider
    # Set up an existing tracer provider
    existing_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    OpenTelemetry.tracer_provider = existing_provider

    Braintrust.init(set_global: false, api_key: "test-key", tracing: true)

    # Should reuse the existing provider (same object)
    assert_same existing_provider, OpenTelemetry.tracer_provider
  end

  def test_init_with_tracing_false_skips_tracing
    # Verify we start with the default proxy provider
    assert_instance_of OpenTelemetry::Internal::ProxyTracerProvider, OpenTelemetry.tracer_provider

    Braintrust.init(set_global: false, api_key: "test-key", tracing: false)

    # Should still be the proxy provider (no tracing setup)
    assert_instance_of OpenTelemetry::Internal::ProxyTracerProvider, OpenTelemetry.tracer_provider
  end

  def test_init_defaults_to_tracing_enabled
    # Verify we start with the default proxy provider
    assert_instance_of OpenTelemetry::Internal::ProxyTracerProvider, OpenTelemetry.tracer_provider

    # Call init without tracing parameter
    Braintrust.init(set_global: false, api_key: "test-key")

    # Should have enabled tracing by default
    assert_instance_of OpenTelemetry::SDK::Trace::TracerProvider, OpenTelemetry.tracer_provider
  end

  def test_init_with_tracing_adds_span_processor
    Braintrust.init(set_global: false, api_key: "test-key", tracing: true)

    provider = OpenTelemetry.tracer_provider
    processors = provider.instance_variable_get(:@span_processors)

    # Should have at least one span processor (Braintrust's)
    refute_empty processors
  end

  def test_init_with_explicit_tracer_provider
    # Create a custom tracer provider
    custom_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

    Braintrust.init(set_global: false, api_key: "test-key", tracing: true, tracer_provider: custom_provider)

    # Should NOT set the custom provider as global (user is managing it themselves)
    refute_same custom_provider, OpenTelemetry.tracer_provider
    # Global should still be the default proxy
    assert_instance_of OpenTelemetry::Internal::ProxyTracerProvider, OpenTelemetry.tracer_provider

    # But should have added span processor to the custom provider
    processors = custom_provider.instance_variable_get(:@span_processors)
    refute_empty processors
  end
end
