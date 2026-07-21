# frozen_string_literal: true

module Braintrust
  module Internal
    # Environment variable utilities.
    module Env
      ENV_AUTO_INSTRUMENT = "BRAINTRUST_AUTO_INSTRUMENT"
      ENV_ENVIRONMENT_NAME = "BRAINTRUST_ENVIRONMENT_NAME"
      ENV_ENVIRONMENT_TYPE = "BRAINTRUST_ENVIRONMENT_TYPE"
      ENV_INSTRUMENT_EXCEPT = "BRAINTRUST_INSTRUMENT_EXCEPT"
      ENV_INSTRUMENT_ONLY = "BRAINTRUST_INSTRUMENT_ONLY"
      ENV_FLUSH_ON_EXIT = "BRAINTRUST_FLUSH_ON_EXIT"

      def self.auto_instrument
        ENV[ENV_AUTO_INSTRUMENT] != "false"
      end

      # Whether to automatically flush spans on program exit. Default: true
      def self.flush_on_exit
        ENV[ENV_FLUSH_ON_EXIT] != "false"
      end

      def self.instrument_except
        parse_list(ENV_INSTRUMENT_EXCEPT)
      end

      def self.instrument_only
        parse_list(ENV_INSTRUMENT_ONLY)
      end

      def self.detect_environment
        env_type = env_value(ENV_ENVIRONMENT_TYPE)
        env_name = env_value(ENV_ENVIRONMENT_NAME)
        if present?(env_type) || present?(env_name)
          return {type: env_type, name: env_name}.compact
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
          return {type: "ci", name: name} if present?(ENV[key])
        end
        return {type: "ci", name: "ci"} if present?(ENV["CI"])

        server_name = detect_server_environment_name
        return {type: "server", name: server_name} if server_name

        deployment_mode_environment(ENV["RAILS_ENV"]) ||
          deployment_mode_environment(ENV["RACK_ENV"])
      end

      # Parse a comma-separated environment variable into an array of symbols.
      # @param key [String] The environment variable name
      # @return [Array<Symbol>, nil] Array of symbols, or nil if not set
      def self.parse_list(key)
        value = ENV[key]
        return nil unless value
        value.split(",").map(&:strip).map(&:to_sym)
      end

      def self.deployment_mode_environment(value)
        return nil unless present?(value)

        normalized = value.strip.downcase
        return {type: "server", name: normalized} if ["production", "staging"].include?(normalized)
        return {type: "local", name: normalized} if ["development", "local"].include?(normalized)

        nil
      end
      private_class_method :deployment_mode_environment

      def self.detect_server_environment_name
        {"VERCEL" => "vercel", "NETLIFY" => "netlify"}.each do |key, name|
          return name if present?(ENV[key])
        end
        return "ecs" if present?(ENV["ECS_CONTAINER_METADATA_URI"]) || present?(ENV["ECS_CONTAINER_METADATA_URI_V4"])

        aws_execution_env = env_value("AWS_EXECUTION_ENV")
        return "ecs" if aws_execution_env&.start_with?("AWS_ECS_")
        return "aws_lambda" if aws_execution_env&.start_with?("AWS_Lambda_")
        return "aws_lambda" if present?(ENV["AWS_LAMBDA_FUNCTION_NAME"])

        {
          "K_SERVICE" => "cloud_run",
          "FUNCTION_TARGET" => "gcp_functions",
          "KUBERNETES_SERVICE_HOST" => "kubernetes",
          "DYNO" => "heroku",
          "FLY_APP_NAME" => "fly",
          "RAILWAY_ENVIRONMENT" => "railway",
          "RENDER_SERVICE_NAME" => "render"
        }.each do |key, name|
          return name if present?(ENV[key])
        end

        nil
      end
      private_class_method :detect_server_environment_name

      def self.env_value(key)
        value = ENV[key]
        value&.strip unless value.nil? || value.strip.empty?
      end
      private_class_method :env_value

      def self.present?(value)
        !value.nil? && !value.strip.empty?
      end
      private_class_method :present?
    end
  end
end
