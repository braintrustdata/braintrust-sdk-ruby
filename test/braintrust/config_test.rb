# frozen_string_literal: true

require "test_helper"

BRAINTRUST_CONFIG_ENV_VALUES = {
  "BRAINTRUST_API_KEY" => ENV["BRAINTRUST_API_KEY"],
  "BRAINTRUST_ORG_NAME" => ENV["BRAINTRUST_ORG_NAME"],
  "BRAINTRUST_APP_URL" => ENV["BRAINTRUST_APP_URL"],
  "BRAINTRUST_API_URL" => ENV["BRAINTRUST_API_URL"]
}.freeze

class Braintrust::ConfigTest < Minitest::Test
  def setup
    # Setup a clean state
    BRAINTRUST_CONFIG_ENV_VALUES.keys.each { |env_var| ENV.delete(env_var) }
  end

  def teardown
    # Restore original env vars
    BRAINTRUST_CONFIG_ENV_VALUES.each do |env_var, env_value|
      if env_value
        ENV[env_var] = env_value
      else
        ENV.delete(env_var)
      end
    end
  end

  def test_parses_api_key_from_env
    ENV["BRAINTRUST_API_KEY"] = "test-key-123"

    config = Braintrust::Config.from_env

    assert_equal "test-key-123", config.api_key
  end

  def test_provides_default_values
    config = Braintrust::Config.from_env

    assert_equal "https://www.braintrust.dev", config.app_url
    assert_equal "https://api.braintrust.dev", config.api_url
  end

  def test_passed_options_override_env_vars
    ENV["BRAINTRUST_API_KEY"] = "env-key"
    ENV["BRAINTRUST_ORG_NAME"] = "env-org"

    config = Braintrust::Config.from_env(
      api_key: "explicit-key",
      org_name: "explicit-org"
    )

    assert_equal "explicit-key", config.api_key
    assert_equal "explicit-org", config.org_name
  end

  def test_env_vars_override_defaults
    ENV["BRAINTRUST_APP_URL"] = "https://custom.braintrust.dev"

    config = Braintrust::Config.from_env

    assert_equal "https://custom.braintrust.dev", config.app_url
  end
end
