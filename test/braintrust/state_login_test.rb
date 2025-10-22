# frozen_string_literal: true

require "test_helper"

class Braintrust::StateLoginTest < Minitest::Test
  def setup
    @api_key = ENV["BRAINTRUST_API_KEY"]
    assert @api_key, "BRAINTRUST_API_KEY environment variable is required for login tests"
  end

  def teardown
    Braintrust::State.instance_variable_set(:@global_state, nil)
  end

  def test_login_fetches_org_info
    state = Braintrust::State.new(
      api_key: @api_key,
      app_url: "https://www.braintrust.dev"
    )

    state.login

    assert state.logged_in
    refute_nil state.org_id
    refute_nil state.org_name
    refute_nil state.api_url
  end

  def test_login_with_invalid_api_key
    state = Braintrust::State.new(
      api_key: "invalid-key",
      app_url: "https://www.braintrust.dev"
    )

    error = assert_raises(Braintrust::Error) do
      state.login
    end

    assert_match(/invalid api key/i, error.message)
  end
end
