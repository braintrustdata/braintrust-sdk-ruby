# frozen_string_literal: true

require "test_helper"
require "opentelemetry/sdk"

# Tests that tracing setup is deferred until after login completes,
# so the OTLP exporter receives the org-specific api_url (not the default).
class Braintrust::StateTracingTest < Minitest::Test
  # The "test-api-key" magic key returns api_url "https://api.ruby-sdk-fixture.com"
  # which differs from the default "https://api.braintrust.dev", making it easy
  # to detect whether the exporter was created before or after login.
  MAGIC_KEY = "test-api-key"
  POST_LOGIN_API_URL = "https://api.ruby-sdk-fixture.com"

  def test_blocking_login_sets_up_tracing_with_post_login_api_url
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    state = Braintrust::State.new(
      api_key: MAGIC_KEY,
      blocking_login: true,
      enable_tracing: true,
      exporter: exporter
    )

    assert state.logged_in
    assert_equal POST_LOGIN_API_URL, state.api_url

    provider = OpenTelemetry.tracer_provider
    assert_kind_of OpenTelemetry::SDK::Trace::TracerProvider, provider

    processors = provider.instance_variable_get(:@span_processors)
    refute_empty processors, "Tracer provider should have span processors after blocking login"
  end

  def test_org_id_sets_up_tracing_immediately
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    state = Braintrust::State.new(
      api_key: "any-key",
      org_id: "test-org-id",
      api_url: "https://custom.example.com",
      enable_tracing: true,
      exporter: exporter
    )

    assert state.logged_in
    assert_equal "https://custom.example.com", state.api_url

    provider = OpenTelemetry.tracer_provider
    assert_kind_of OpenTelemetry::SDK::Trace::TracerProvider, provider

    processors = provider.instance_variable_get(:@span_processors)
    refute_empty processors, "Tracer provider should have span processors when org_id is provided"
  end

  def test_async_login_defers_tracing_until_login_completes
    assert_in_fork do
      exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
      state = Braintrust::State.new(
        api_key: MAGIC_KEY,
        enable_tracing: true,
        exporter: exporter
      )

      # Login hasn't completed yet (though with magic key it's fast, check the result)
      state.wait_for_login(5)

      assert state.logged_in
      assert_equal POST_LOGIN_API_URL, state.api_url

      provider = OpenTelemetry.tracer_provider
      assert_kind_of OpenTelemetry::SDK::Trace::TracerProvider, provider

      processors = provider.instance_variable_get(:@span_processors)
      refute_empty processors, "Tracer provider should have span processors after async login"
    end
  end

  def test_tracing_setup_is_idempotent
    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    state = Braintrust::State.new(
      api_key: MAGIC_KEY,
      blocking_login: true,
      enable_tracing: true,
      exporter: exporter
    )

    provider = OpenTelemetry.tracer_provider
    processors_before = provider.instance_variable_get(:@span_processors).size

    # Calling login again should not add duplicate processors
    state.login

    processors_after = provider.instance_variable_get(:@span_processors).size
    assert_equal processors_before, processors_after,
      "Repeated login should not add duplicate span processors"
  end

  def test_tracing_disabled_skips_setup
    Braintrust::State.new(
      api_key: "any-key",
      org_id: "test-org-id",
      enable_tracing: false
    )

    provider = OpenTelemetry.tracer_provider
    refute_kind_of OpenTelemetry::SDK::Trace::TracerProvider, provider,
      "Global tracer provider should remain a proxy when tracing is disabled"
  end
end
