# frozen_string_literal: true

require "test_helper"

class Braintrust::Internal::EnvTest < Minitest::Test
  DETECTION_ENV_KEYS = [
    "AWS_EXECUTION_ENV",
    "AWS_LAMBDA_FUNCTION_NAME",
    "BITBUCKET_BUILD_NUMBER",
    "BRAINTRUST_ENVIRONMENT_NAME",
    "BRAINTRUST_ENVIRONMENT_TYPE",
    "BUILDKITE",
    "CI",
    "CIRCLECI",
    "DYNO",
    "ECS_CONTAINER_METADATA_URI",
    "ECS_CONTAINER_METADATA_URI_V4",
    "FLY_APP_NAME",
    "FUNCTION_TARGET",
    "GITHUB_ACTIONS",
    "GITLAB_CI",
    "JENKINS_HOME",
    "JENKINS_URL",
    "K_SERVICE",
    "KUBERNETES_SERVICE_HOST",
    "NETLIFY",
    "RACK_ENV",
    "RAILS_ENV",
    "RAILWAY_ENVIRONMENT",
    "RENDER_SERVICE_NAME",
    "TEAMCITY_VERSION",
    "TF_BUILD",
    "TRAVIS",
    "VERCEL"
  ].freeze

  def test_environment_type_and_name_override_auto_detection
    with_detection_env(
      "BRAINTRUST_ENVIRONMENT_TYPE" => "ci",
      "BRAINTRUST_ENVIRONMENT_NAME" => "github_actions",
      "GITHUB_ACTIONS" => "true"
    ) do
      assert_equal({type: "ci", name: "github_actions"}, Braintrust::Internal::Env.detect_environment)
    end
  end

  def test_environment_name_without_type_is_preserved
    with_detection_env("BRAINTRUST_ENVIRONMENT_NAME" => "staging") do
      assert_equal({name: "staging"}, Braintrust::Internal::Env.detect_environment)
    end
  end

  def test_aws_execution_env_classifies_ecs_before_lambda
    with_detection_env("AWS_EXECUTION_ENV" => "AWS_ECS_FARGATE") do
      assert_equal({type: "server", name: "ecs"}, Braintrust::Internal::Env.detect_environment)
    end
  end

  def test_aws_execution_env_classifies_lambda_when_lambda_specific
    with_detection_env("AWS_EXECUTION_ENV" => "AWS_Lambda_ruby3.2") do
      assert_equal({type: "server", name: "aws_lambda"}, Braintrust::Internal::Env.detect_environment)
    end
  end

  private

  def with_detection_env(values)
    original = DETECTION_ENV_KEYS.to_h { |key| [key, ENV[key]] }
    DETECTION_ENV_KEYS.each { |key| ENV.delete(key) }
    values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
