# frozen_string_literal: true

require_relative "braintrust/version"
require_relative "braintrust/config"
require_relative "braintrust/state"
require_relative "braintrust/trace"
require_relative "braintrust/internal/experiments"
require_relative "braintrust/eval"

# Braintrust Ruby SDK
#
# OpenTelemetry-based SDK for Braintrust with tracing, OpenAI integration, and evals.
#
# @example Initialize with global state
#   Braintrust.init(
#     api_key: ENV['BRAINTRUST_API_KEY'],
#     project: "my-project"
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
  # Creates a State from config (ENV + options) and optionally sets it as global
  #
  # @param set_global [Boolean] whether to set as global state (default: true)
  # @param blocking_login [Boolean] whether to block and login immediately (default: false)
  # @param api_key [String, nil] Braintrust API key (overrides BRAINTRUST_API_KEY env var)
  # @param org_name [String, nil] Organization name (overrides BRAINTRUST_ORG_NAME env var)
  # @param default_parent [String, nil] Default parent for spans (overrides BRAINTRUST_DEFAULT_PROJECT env var, format: "project_name:my-project" or "project_id:uuid")
  # @param app_url [String, nil] App URL (overrides BRAINTRUST_APP_URL env var, default: https://www.braintrust.dev)
  # @param api_url [String, nil] API URL (overrides BRAINTRUST_API_URL env var, default: https://api.braintrust.dev)
  # @return [State] the created state
  def self.init(set_global: true, blocking_login: false, **options)
    config = Config.from_env(**options)
    state = State.new(
      api_key: config.api_key,
      org_name: config.org_name,
      default_parent: config.default_parent,
      app_url: config.app_url,
      api_url: config.api_url
    )

    State.global = state if set_global

    state.login if blocking_login

    state
  end

  # Get the current global state
  # @return [State, nil] the global state, or nil if not set
  def self.current_state
    State.global
  end
end
