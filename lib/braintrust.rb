# frozen_string_literal: true

require_relative "braintrust/version"
require_relative "braintrust/config"
require_relative "braintrust/state"
require_relative "braintrust/trace"
require_relative "braintrust/api"
require_relative "braintrust/internal/experiments"
require_relative "braintrust/eval"

# Braintrust Ruby SDK
#
# OpenTelemetry-based SDK for Braintrust with tracing, OpenAI integration, and evals.
#
# @example Initialize with global state
#   Braintrust.init(
#     api_key: ENV['BRAINTRUST_API_KEY'],
#     default_project: "my-project"
#   )
#
# @example Initialize with explicit state
#   state = Braintrust.init(
#     api_key: ENV['BRAINTRUST_API_KEY'],
#     set_global: false
#   )
module Braintrust
  class Error < StandardError; end

  # Initialize Braintrust SDK
  #
  # @param api_key [String, nil] Braintrust API key (overrides BRAINTRUST_API_KEY env var)
  # @param org_name [String, nil] Organization name (overrides BRAINTRUST_ORG_NAME env var)
  # @param default_project [String, nil] Default project for spans (overrides BRAINTRUST_DEFAULT_PROJECT env var, format: "project_name:my-project" or "project_id:uuid")
  # @param app_url [String, nil] App URL (overrides BRAINTRUST_APP_URL env var, default: https://www.braintrust.dev)
  # @param api_url [String, nil] API URL (overrides BRAINTRUST_API_URL env var, default: https://api.braintrust.dev)
  # @param set_global [Boolean] Whether to set as global state (default: true)
  # @param blocking_login [Boolean] Whether to block and login synchronously (default: false - async background login)
  # @param enable_tracing [Boolean] Whether to enable OpenTelemetry tracing (default: true)
  # @param tracer_provider [TracerProvider, nil] Optional tracer provider to use instead of creating one
  # @param filter_ai_spans [Boolean, nil] Enable AI span filtering (overrides BRAINTRUST_OTEL_FILTER_AI_SPANS env var)
  # @param span_filter_funcs [Array<Proc>, nil] Custom span filter functions
  # @param exporter [Exporter, nil] Optional exporter override (for testing)
  # @return [State] the created state
  def self.init(api_key: nil, org_name: nil, default_project: nil, app_url: nil, api_url: nil, set_global: true, blocking_login: false, enable_tracing: true, tracer_provider: nil, filter_ai_spans: nil, span_filter_funcs: nil, exporter: nil)
    state = State.from_env(
      api_key: api_key,
      org_name: org_name,
      default_project: default_project,
      app_url: app_url,
      api_url: api_url,
      blocking_login: blocking_login,
      enable_tracing: enable_tracing,
      tracer_provider: tracer_provider,
      filter_ai_spans: filter_ai_spans,
      span_filter_funcs: span_filter_funcs,
      exporter: exporter
    )

    State.global = state if set_global

    state
  end

  # Get the current global state
  # @return [State, nil] the global state, or nil if not set
  def self.current_state
    State.global
  end
end
