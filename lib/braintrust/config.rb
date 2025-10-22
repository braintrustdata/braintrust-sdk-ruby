# frozen_string_literal: true

module Braintrust
  # Configuration object that reads from environment variables
  # and allows overriding with explicit options
  class Config
    attr_reader :api_key, :org_name, :default_parent, :app_url, :api_url

    def initialize(api_key: nil, org_name: nil, default_parent: nil, app_url: nil, api_url: nil)
      @api_key = api_key
      @org_name = org_name
      @default_parent = default_parent
      @app_url = app_url
      @api_url = api_url
    end

    # Create a Config from environment variables, with option overrides
    # Passed-in options take priority over ENV vars
    def self.from_env(**options)
      defaults = {
        api_key: ENV["BRAINTRUST_API_KEY"],
        org_name: ENV["BRAINTRUST_ORG_NAME"],
        default_parent: ENV["BRAINTRUST_DEFAULT_PROJECT"],
        app_url: ENV["BRAINTRUST_APP_URL"] || "https://www.braintrust.dev",
        api_url: ENV["BRAINTRUST_API_URL"] || "https://api.braintrust.dev"
      }
      new(**defaults.merge(options))
    end
  end
end
