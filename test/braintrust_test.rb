# frozen_string_literal: true

require "test_helper"

class BraintrustTest < Minitest::Test
  def setup
    # Save original env vars
    @original_api_key = ENV["BRAINTRUST_API_KEY"]
    @original_default_project = ENV["BRAINTRUST_DEFAULT_PROJECT"]

    # Reset global state before each test
    Braintrust::State.instance_variable_set(:@global_state, nil)

    # Reset global tracer provider to default proxy
    OpenTelemetry.tracer_provider = OpenTelemetry::Internal::ProxyTracerProvider.new
  end

  def teardown
    # Reset global tracer provider to default proxy
    OpenTelemetry.tracer_provider = OpenTelemetry::Internal::ProxyTracerProvider.new

    # Restore original env vars
    if @original_api_key
      ENV["BRAINTRUST_API_KEY"] = @original_api_key
    else
      ENV.delete("BRAINTRUST_API_KEY")
    end

    if @original_default_project
      ENV["BRAINTRUST_DEFAULT_PROJECT"] = @original_default_project
    else
      ENV.delete("BRAINTRUST_DEFAULT_PROJECT")
    end

    # Call parent teardown (includes global state cleanup from test_helper)
    super
  end

  # Note: These tests use "test-api-key" which triggers fake auth in API::Internal::Auth.login
  # This avoids real HTTP requests while still testing the full init flow

  def test_init_sets_global_state_by_default
    state = Braintrust.init(api_key: "test-api-key")

    assert_same state, Braintrust.current_state
    assert_equal "test-api-key", state.api_key
  end

  def test_init_with_set_global_false_returns_state
    # Ensure global state is clean before test
    Braintrust::State.instance_variable_set(:@global_state, nil)

    state = Braintrust.init(api_key: "test-api-key", set_global: false)

    assert_equal "test-api-key", state.api_key
    assert_nil Braintrust.current_state
  end

  def test_init_merges_options_with_env
    ENV["BRAINTRUST_API_KEY"] = "env-key"

    # Note: Can't test api_key override with test-api-key since we need the fake auth
    state = Braintrust.init(api_key: "test-api-key", set_global: false, default_project: "my-project")

    assert_equal "test-api-key", state.api_key
    assert_equal "my-project", state.default_project
  end

  def test_init_with_tracing_true_creates_tracer_provider
    # Verify we start with the default proxy provider
    assert_instance_of OpenTelemetry::Internal::ProxyTracerProvider, OpenTelemetry.tracer_provider

    Braintrust.init(api_key: "test-api-key", set_global: false, enable_tracing: true, blocking_login: true)

    # Should have created and set a real TracerProvider
    assert_instance_of OpenTelemetry::SDK::Trace::TracerProvider, OpenTelemetry.tracer_provider
  end

  def test_init_with_tracing_true_uses_existing_provider
    # Set up an existing tracer provider
    existing_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    OpenTelemetry.tracer_provider = existing_provider

    Braintrust.init(api_key: "test-api-key", set_global: false, enable_tracing: true)

    # Should reuse the existing provider (same object)
    assert_same existing_provider, OpenTelemetry.tracer_provider
  end

  def test_init_with_tracing_false_skips_tracing
    # Verify we start with the default proxy provider
    assert_instance_of OpenTelemetry::Internal::ProxyTracerProvider, OpenTelemetry.tracer_provider

    Braintrust.init(api_key: "test-api-key", set_global: false, enable_tracing: false)

    # Should still be the proxy provider (no tracing setup)
    assert_instance_of OpenTelemetry::Internal::ProxyTracerProvider, OpenTelemetry.tracer_provider
  end

  def test_init_defaults_to_tracing_enabled
    # Verify we start with the default proxy provider
    assert_instance_of OpenTelemetry::Internal::ProxyTracerProvider, OpenTelemetry.tracer_provider

    # Call init without tracing parameter
    Braintrust.init(api_key: "test-api-key", set_global: false, blocking_login: true)

    # Should have enabled tracing by default
    assert_instance_of OpenTelemetry::SDK::Trace::TracerProvider, OpenTelemetry.tracer_provider
  end

  def test_init_with_tracing_adds_span_processor
    Braintrust.init(api_key: "test-api-key", set_global: false, enable_tracing: true, blocking_login: true)

    provider = OpenTelemetry.tracer_provider
    processors = provider.instance_variable_get(:@span_processors)

    # Should have at least one span processor (Braintrust's)
    refute_empty processors
  end

  def test_init_with_explicit_tracer_provider
    # Create a custom tracer provider
    custom_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

    Braintrust.init(api_key: "test-api-key", set_global: false, enable_tracing: true, tracer_provider: custom_provider, blocking_login: true)

    # Should NOT set the custom provider as global (user is managing it themselves)
    refute_same custom_provider, OpenTelemetry.tracer_provider
    # Global should still be the default proxy
    assert_instance_of OpenTelemetry::Internal::ProxyTracerProvider, OpenTelemetry.tracer_provider

    # But should have added span processor to the custom provider
    processors = custom_provider.instance_variable_get(:@span_processors)
    refute_empty processors
  end

  def test_default_project_from_env_flows_to_spans
    # Purpose: Verify that BRAINTRUST_DEFAULT_PROJECT env var flows through Config -> State -> SpanProcessor
    # and that spans created with tracing enabled have the correct braintrust.parent attribute
    # The env var contains just the project name, SpanProcessor formats it as "project_name:value"
    ENV["BRAINTRUST_API_KEY"] = "test-key"
    ENV["BRAINTRUST_DEFAULT_PROJECT"] = "env-project"

    # Set up test rig with tracing
    rig = setup_otel_test_rig(default_project: "env-project")

    # Create a span
    tracer = rig.tracer("test")
    span = tracer.start_span("test-span")
    span.finish

    # Drain spans and verify - should be formatted as "project_name:env-project"
    spans = rig.drain
    assert_equal 1, spans.length

    span_data = spans.first
    assert_equal "project_name:env-project", span_data.attributes["braintrust.parent"]
  end

  def test_default_project_from_parameter_overrides_env
    # Purpose: Verify that explicit default_project parameter to init() overrides BRAINTRUST_DEFAULT_PROJECT env var
    # This ensures users can override the env var at runtime
    # The parameter takes just the project name, SpanProcessor formats it as "project_name:value"
    ENV["BRAINTRUST_API_KEY"] = "test-key"
    ENV["BRAINTRUST_DEFAULT_PROJECT"] = "env-project"

    # Set up test rig with explicit parameter (should override env var)
    rig = setup_otel_test_rig(default_project: "param-project")

    # Create a span
    tracer = rig.tracer("test")
    span = tracer.start_span("test-span")
    span.finish

    # Drain spans and verify parameter won - should be formatted as "project_name:param-project"
    spans = rig.drain
    assert_equal 1, spans.length

    span_data = spans.first
    assert_equal "project_name:param-project", span_data.attributes["braintrust.parent"]
  end

  def test_init_calls_auto_instrument_with_config
    called_with = :not_called

    Braintrust.stub(:auto_instrument!, ->(config) { called_with = config }) do
      Braintrust.init(api_key: "test-api-key", auto_instrument: {only: [:openai]})
    end

    assert_equal({only: [:openai]}, called_with)
  end

  def test_init_calls_auto_instrument_with_nil_by_default
    called_with = :not_called

    Braintrust.stub(:auto_instrument!, ->(config) { called_with = config }) do
      Braintrust.init(api_key: "test-api-key")
    end

    assert_nil called_with
  end
end
