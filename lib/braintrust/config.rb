# frozen_string_literal: true

module Braintrust
  # Configuration object that reads from environment variables
  # and allows overriding with explicit options
  class Config
    attr_reader :api_key, :org_name, :default_project, :app_url, :api_url

    def initialize(api_key: nil, org_name: nil, default_project: nil, app_url: nil, api_url: nil)
      @api_key = api_key
      @org_name = org_name
      @default_project = default_project
      @app_url = app_url
      @api_url = api_url
    end

    # Create a Config from environment variables, with option overrides
    # Passed-in options take priority over ENV vars
    # @param api_key [String, nil] Braintrust API key (overrides BRAINTRUST_API_KEY env var)
    # @param org_name [String, nil] Organization name (overrides BRAINTRUST_ORG_NAME env var)
    # @param default_project [String, nil] Default project (overrides BRAINTRUST_DEFAULT_PROJECT env var)
    # @param app_url [String, nil] App URL (overrides BRAINTRUST_APP_URL env var)
    # @param api_url [String, nil] API URL (overrides BRAINTRUST_API_URL env var)
    # @return [Config] the created config
    def self.from_env(api_key: nil, org_name: nil, default_project: nil, app_url: nil, api_url: nil)
      new(
        api_key: api_key || ENV["BRAINTRUST_API_KEY"],
        org_name: org_name || ENV["BRAINTRUST_ORG_NAME"],
        default_project: default_project || ENV["BRAINTRUST_DEFAULT_PROJECT"],
        app_url: app_url || ENV["BRAINTRUST_APP_URL"] || "https://www.braintrust.dev",
        api_url: api_url || ENV["BRAINTRUST_API_URL"] || "https://api.braintrust.dev"
      )
    end
  end
end
