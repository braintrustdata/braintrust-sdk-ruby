# frozen_string_literal: true

require "test_helper"

class Braintrust::ConfigTest < Minitest::Test
  def setup
    # Save original env vars
    @original_api_key = ENV["BRAINTRUST_API_KEY"]
    @original_org_name = ENV["BRAINTRUST_ORG_NAME"]
    @original_app_url = ENV["BRAINTRUST_APP_URL"]
  end

  def teardown
    # Restore original env vars
    if @original_api_key
      ENV["BRAINTRUST_API_KEY"] = @original_api_key
    else
      ENV.delete("BRAINTRUST_API_KEY")
    end

    if @original_org_name
      ENV["BRAINTRUST_ORG_NAME"] = @original_org_name
    else
      ENV.delete("BRAINTRUST_ORG_NAME")
    end

    if @original_app_url
      ENV["BRAINTRUST_APP_URL"] = @original_app_url
    else
      ENV.delete("BRAINTRUST_APP_URL")
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
