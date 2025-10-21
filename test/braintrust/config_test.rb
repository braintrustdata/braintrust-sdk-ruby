# frozen_string_literal: true

require "test_helper"

class Braintrust::ConfigTest < Minitest::Test
  def test_parses_api_key_from_env
    ENV["BRAINTRUST_API_KEY"] = "test-key-123"

    config = Braintrust::Config.from_env

    assert_equal "test-key-123", config.api_key
  ensure
    ENV.delete("BRAINTRUST_API_KEY")
  end
end
