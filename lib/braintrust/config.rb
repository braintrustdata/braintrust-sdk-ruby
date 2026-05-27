# frozen_string_literal: true

require_relative "internal/api_key_resolver"

module Braintrust
  # Configuration object that reads from environment variables
  # and allows overriding with explicit options
  class Config
    attr_reader :org_name, :default_project, :app_url, :api_url,
      :filter_ai_spans, :span_filter_funcs

    def initialize(api_key: nil, org_name: nil, default_project: nil, app_url: nil, api_url: nil,
      filter_ai_spans: nil, span_filter_funcs: nil)
      @api_key = api_key
      @api_key_resolver = nil
      @org_name = org_name
      @default_project = default_project
      @app_url = app_url
      @api_url = api_url
      @filter_ai_spans = filter_ai_spans
      @span_filter_funcs = span_filter_funcs || []
    end

    def api_key
      @api_key = @api_key_resolver.api_key if @api_key.nil? && @api_key_resolver
      @api_key
    end

    # Create a Config from environment variables, with option overrides
    # Passed-in options take priority over ENV vars
    # @param api_key [String, nil] Braintrust API key (overrides BRAINTRUST_API_KEY env var)
    # @param org_name [String, nil] Organization name (overrides BRAINTRUST_ORG_NAME env var)
    # @param default_project [String, nil] Default project (overrides BRAINTRUST_DEFAULT_PROJECT env var)
    # @param app_url [String, nil] App URL (overrides BRAINTRUST_APP_URL env var)
    # @param api_url [String, nil] API URL (overrides BRAINTRUST_API_URL env var)
    # @param filter_ai_spans [Boolean, nil] Enable AI span filtering (overrides BRAINTRUST_OTEL_FILTER_AI_SPANS env var)
    # @param span_filter_funcs [Array<Proc>, nil] Custom span filter functions
    # @return [Config] the created config
    def self.from_env(api_key: nil, org_name: nil, default_project: nil, app_url: nil, api_url: nil,
      filter_ai_spans: nil, span_filter_funcs: nil)
      api_key_resolver = Internal::ApiKeyResolver.new(explicit_api_key: api_key)

      # Parse filter_ai_spans from ENV if not explicitly provided
      env_filter_ai_spans = ENV["BRAINTRUST_OTEL_FILTER_AI_SPANS"]
      filter_ai_spans_value = if filter_ai_spans.nil?
        env_filter_ai_spans&.downcase == "true"
      else
        filter_ai_spans
      end

      config = new(
        api_key: api_key_resolver.immediate_api_key,
        org_name: org_name || ENV["BRAINTRUST_ORG_NAME"],
        default_project: default_project || ENV["BRAINTRUST_DEFAULT_PROJECT"],
        app_url: app_url || ENV["BRAINTRUST_APP_URL"] || "https://www.braintrust.dev",
        api_url: api_url || ENV["BRAINTRUST_API_URL"] || "https://api.braintrust.dev",
        filter_ai_spans: filter_ai_spans_value,
        span_filter_funcs: span_filter_funcs
      )
      config.instance_variable_set(:@api_key_resolver, api_key_resolver)
      config
    end
  end
end
