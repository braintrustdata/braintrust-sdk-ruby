# frozen_string_literal: true

require_relative "internal/api_key_resolver"

module Braintrust
  # Configuration object that reads from environment variables
  # and allows overriding with explicit options
  class Config
    attr_reader :api_key, :org_name, :default_project, :app_url, :api_url,
      :filter_ai_spans, :span_filter_funcs, :environment

    def initialize(api_key: nil, org_name: nil, default_project: nil, app_url: nil, api_url: nil,
      filter_ai_spans: nil, span_filter_funcs: nil, environment: nil)
      @api_key = api_key
      @org_name = org_name
      @default_project = default_project
      @app_url = app_url
      @api_url = api_url
      @filter_ai_spans = filter_ai_spans
      @span_filter_funcs = span_filter_funcs || []
      @environment = environment
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
    # @param environment [Hash, nil] Span-origin environment override, e.g. { type: "ci", name: "github_actions" }
    # @return [Config] the created config
    def self.from_env(api_key: nil, org_name: nil, default_project: nil, app_url: nil, api_url: nil,
      filter_ai_spans: nil, span_filter_funcs: nil, environment: nil)
      # Parse filter_ai_spans from ENV if not explicitly provided
      env_filter_ai_spans = ENV["BRAINTRUST_OTEL_FILTER_AI_SPANS"]
      filter_ai_spans_value = if filter_ai_spans.nil?
        env_filter_ai_spans&.downcase == "true"
      else
        filter_ai_spans
      end

      new(
        api_key: Internal::ApiKeyResolver.resolve(explicit_api_key: api_key),
        org_name: org_name || ENV["BRAINTRUST_ORG_NAME"],
        default_project: default_project || ENV["BRAINTRUST_DEFAULT_PROJECT"],
        app_url: app_url || ENV["BRAINTRUST_APP_URL"] || "https://www.braintrust.dev",
        api_url: api_url || ENV["BRAINTRUST_API_URL"] || "https://api.braintrust.dev",
        filter_ai_spans: filter_ai_spans_value,
        span_filter_funcs: span_filter_funcs,
        environment: detect_environment(environment)
      )
    end

    def self.detect_environment(explicit = nil)
      return normalize_environment(explicit) if explicit

      env_type = env_value("BRAINTRUST_ENVIRONMENT_TYPE")
      if env_type && !env_type.empty?
        env_name = env_value("BRAINTRUST_ENVIRONMENT_NAME")
        return { type: env_type, name: env_name }.compact
      end

      {
        "GITHUB_ACTIONS" => "github_actions",
        "GITLAB_CI" => "gitlab_ci",
        "CIRCLECI" => "circleci",
        "BUILDKITE" => "buildkite",
        "JENKINS_URL" => "jenkins",
        "JENKINS_HOME" => "jenkins",
        "TF_BUILD" => "azure_pipelines",
        "TEAMCITY_VERSION" => "teamcity",
        "TRAVIS" => "travis",
        "BITBUCKET_BUILD_NUMBER" => "bitbucket"
      }.each do |key, name|
        return { type: "ci", name: name } if process_env_value(key)
      end
      return { type: "ci", name: "ci" } if process_env_value("CI")

      {
        "VERCEL" => "vercel",
        "NETLIFY" => "netlify",
        "AWS_LAMBDA_FUNCTION_NAME" => "aws_lambda",
        "AWS_EXECUTION_ENV" => "aws_lambda",
        "K_SERVICE" => "cloud_run",
        "FUNCTION_TARGET" => "gcp_functions",
        "KUBERNETES_SERVICE_HOST" => "kubernetes",
        "ECS_CONTAINER_METADATA_URI" => "ecs",
        "ECS_CONTAINER_METADATA_URI_V4" => "ecs",
        "DYNO" => "heroku",
        "FLY_APP_NAME" => "fly",
        "RAILWAY_ENVIRONMENT" => "railway",
        "RENDER_SERVICE_NAME" => "render"
      }.each do |key, name|
        return { type: "server", name: name } if process_env_value(key)
      end

      deployment_mode_environment(process_env_value("RAILS_ENV")) ||
        deployment_mode_environment(process_env_value("RACK_ENV"))
    end

    def self.normalize_environment(environment)
      type = environment[:type] || environment["type"]
      name = environment[:name] || environment["name"]
      { type: type, name: name }.compact
    end

    def self.deployment_mode_environment(value)
      return nil if value.nil? || value.empty?

      normalized = value.downcase
      return { type: "server", name: normalized } if ["production", "staging"].include?(normalized)
      return { type: "local", name: normalized } if ["development", "local"].include?(normalized)

      nil
    end

    def self.env_value(key)
      value = ENV[key]
      value = read_braintrust_env_file_value(key) if value.nil? || value.strip.empty?
      value&.strip
    end

    def self.process_env_value(key)
      value = ENV[key]
      value&.strip unless value.nil? || value.strip.empty?
    end

    def self.read_braintrust_env_file_value(key)
      dir = Dir.pwd
      65.times do
        path = File.join(dir, ".env.braintrust")
        if File.file?(path)
          File.foreach(path) do |line|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?("#")

            name, value = stripped.split("=", 2)
            next unless name&.strip == key

            return value&.strip&.delete_prefix('"')&.delete_suffix('"')&.delete_prefix("'")&.delete_suffix("'")
          end
          return nil
        end

        parent = File.dirname(dir)
        return nil if parent == dir

        dir = parent
      end
      nil
    rescue
      nil
    end
  end
end
