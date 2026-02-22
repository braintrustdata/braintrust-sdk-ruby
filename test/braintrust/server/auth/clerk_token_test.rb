# frozen_string_literal: true

require "test_helper"
require "braintrust/server"

# Tests for the ClerkToken auth strategy.
# Uses WebMock (via VCR's hook) to stub HTTP calls to the Braintrust app endpoint.
class Braintrust::Server::Auth::ClerkTokenTest < Minitest::Test
  ClerkToken = Braintrust::Server::Auth::ClerkToken

  LOGIN_ENDPOINT = "#{ClerkToken::DEFAULT_APP_URL}#{ClerkToken::LOGIN_PATH}"

  def setup
    @strategy = ClerkToken.new
  end

  def test_returns_nil_when_no_token_header
    env = {}

    result = @strategy.authenticate(env)

    assert_nil result
  end

  def test_returns_nil_when_authorization_header_is_nil
    env = {ClerkToken::RACK_AUTH_HEADER => nil}

    result = @strategy.authenticate(env)

    assert_nil result
  end

  def test_returns_auth_context_on_successful_validation
    VCR.turned_off do
      login_response = {"org_id" => "org-456", "org_name" => "test-org"}
      stub_request(:post, LOGIN_ENDPOINT)
        .with(
          body: {token: "clerk-session-token"}.to_json,
          headers: {"Content-Type" => "application/json"}
        )
        .to_return(
          status: 200,
          body: login_response.to_json,
          headers: {"Content-Type" => "application/json"}
        )

      env = {ClerkToken::RACK_AUTH_HEADER => "Bearer clerk-session-token"}
      result = @strategy.authenticate(env)

      assert_equal "clerk-session-token", result["api_key"]
      assert_equal "org-456", result["org_id"]
      assert_equal "test-org", result["org_name"]
      assert_equal ClerkToken::DEFAULT_APP_URL, result["app_url"]
    end
  end

  def test_prefers_org_name_from_request_header
    VCR.turned_off do
      login_response = {"org_id" => "org-456", "org_name" => "login-org"}
      stub_request(:post, LOGIN_ENDPOINT)
        .to_return(status: 200, body: login_response.to_json)

      env = {
        ClerkToken::RACK_AUTH_HEADER => "Bearer token",
        ClerkToken::RACK_ORG_NAME_HEADER => "header-org"
      }
      result = @strategy.authenticate(env)

      assert_equal "header-org", result["org_name"]
    end
  end

  def test_returns_nil_on_401_response
    VCR.turned_off do
      stub_request(:post, LOGIN_ENDPOINT)
        .to_return(status: 401, body: '{"error":"invalid token"}')

      env = {ClerkToken::RACK_AUTH_HEADER => "Bearer bad-token"}
      result = @strategy.authenticate(env)

      assert_nil result
    end
  end

  def test_returns_nil_on_500_response
    VCR.turned_off do
      stub_request(:post, LOGIN_ENDPOINT)
        .to_return(status: 500, body: "Internal Server Error")

      env = {ClerkToken::RACK_AUTH_HEADER => "Bearer some-token"}
      result = @strategy.authenticate(env)

      assert_nil result
    end
  end

  def test_returns_nil_on_network_error
    VCR.turned_off do
      stub_request(:post, LOGIN_ENDPOINT)
        .to_raise(Errno::ECONNREFUSED)

      env = {ClerkToken::RACK_AUTH_HEADER => "Bearer some-token"}
      result = @strategy.authenticate(env)

      assert_nil result
    end
  end

  def test_returns_nil_on_timeout
    VCR.turned_off do
      stub_request(:post, LOGIN_ENDPOINT)
        .to_raise(Net::ReadTimeout)

      env = {ClerkToken::RACK_AUTH_HEADER => "Bearer some-token"}
      result = @strategy.authenticate(env)

      assert_nil result
    end
  end

  def test_sends_token_as_json_post_body
    VCR.turned_off do
      request_stub = stub_request(:post, LOGIN_ENDPOINT)
        .with(
          body: {token: "my-clerk-jwt"}.to_json,
          headers: {"Content-Type" => "application/json"}
        )
        .to_return(status: 200, body: "{}")

      env = {ClerkToken::RACK_AUTH_HEADER => "Bearer my-clerk-jwt"}
      @strategy.authenticate(env)

      assert_requested request_stub
    end
  end

  def test_uses_custom_app_url
    custom_url = "https://custom.braintrust.example.com"
    strategy = ClerkToken.new(app_url: custom_url)

    VCR.turned_off do
      stub_request(:post, "#{custom_url}#{ClerkToken::LOGIN_PATH}")
        .to_return(status: 200, body: '{"org_id":"org-1"}')

      env = {ClerkToken::RACK_AUTH_HEADER => "Bearer some-token"}
      result = strategy.authenticate(env)

      assert_equal "some-token", result["api_key"]
      assert_equal custom_url, result["app_url"]
    end
  end

  def test_defaults_app_url_to_braintrust_dev
    VCR.turned_off do
      stub = stub_request(:post, LOGIN_ENDPOINT)
        .to_return(status: 200, body: '{"ok":true}')

      env = {ClerkToken::RACK_AUTH_HEADER => "Bearer token"}
      @strategy.authenticate(env)

      assert_requested stub
    end
  end
end
