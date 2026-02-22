# frozen_string_literal: true

require "test_helper"
require "braintrust/server"

# Tests for the ClerkToken auth strategy.
# Uses WebMock (via VCR's hook) to stub HTTP calls to the Braintrust app endpoint.
class Braintrust::Server::Auth::ClerkTokenTest < Minitest::Test
  APP_URL = "https://www.braintrust.dev"
  LOGIN_ENDPOINT = "#{APP_URL}/api/apikey/login"

  def setup
    @strategy = Braintrust::Server::Auth::ClerkToken.new
  end

  def test_returns_nil_when_no_token_header
    env = {}

    result = @strategy.authenticate(env)

    assert_nil result
  end

  def test_returns_nil_when_token_header_is_nil
    env = {"HTTP_X_BT_AUTH_TOKEN" => nil}

    result = @strategy.authenticate(env)

    assert_nil result
  end

  def test_returns_parsed_body_on_successful_validation
    VCR.turned_off do
      response_body = {"api_key" => "br-key-abc123", "org_id" => "org-456"}
      stub_request(:post, LOGIN_ENDPOINT)
        .with(
          body: {token: "clerk-session-token"}.to_json,
          headers: {"Content-Type" => "application/json"}
        )
        .to_return(
          status: 200,
          body: response_body.to_json,
          headers: {"Content-Type" => "application/json"}
        )

      env = {"HTTP_X_BT_AUTH_TOKEN" => "clerk-session-token"}
      result = @strategy.authenticate(env)

      assert_equal response_body, result
    end
  end

  def test_returns_nil_on_401_response
    VCR.turned_off do
      stub_request(:post, LOGIN_ENDPOINT)
        .to_return(status: 401, body: '{"error":"invalid token"}')

      env = {"HTTP_X_BT_AUTH_TOKEN" => "bad-token"}
      result = @strategy.authenticate(env)

      assert_nil result
    end
  end

  def test_returns_nil_on_500_response
    VCR.turned_off do
      stub_request(:post, LOGIN_ENDPOINT)
        .to_return(status: 500, body: "Internal Server Error")

      env = {"HTTP_X_BT_AUTH_TOKEN" => "some-token"}
      result = @strategy.authenticate(env)

      assert_nil result
    end
  end

  def test_returns_nil_on_network_error
    VCR.turned_off do
      stub_request(:post, LOGIN_ENDPOINT)
        .to_raise(Errno::ECONNREFUSED)

      env = {"HTTP_X_BT_AUTH_TOKEN" => "some-token"}
      result = @strategy.authenticate(env)

      assert_nil result
    end
  end

  def test_returns_nil_on_timeout
    VCR.turned_off do
      stub_request(:post, LOGIN_ENDPOINT)
        .to_raise(Net::ReadTimeout)

      env = {"HTTP_X_BT_AUTH_TOKEN" => "some-token"}
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
        .to_return(status: 200, body: "{}".to_json)

      env = {"HTTP_X_BT_AUTH_TOKEN" => "my-clerk-jwt"}
      @strategy.authenticate(env)

      assert_requested request_stub
    end
  end

  def test_uses_custom_app_url
    custom_url = "https://custom.braintrust.example.com"
    strategy = Braintrust::Server::Auth::ClerkToken.new(app_url: custom_url)

    VCR.turned_off do
      stub_request(:post, "#{custom_url}/api/apikey/login")
        .to_return(status: 200, body: '{"api_key":"key-123"}')

      env = {"HTTP_X_BT_AUTH_TOKEN" => "some-token"}
      result = strategy.authenticate(env)

      assert_equal({"api_key" => "key-123"}, result)
    end
  end

  def test_defaults_app_url_to_braintrust_dev
    VCR.turned_off do
      stub = stub_request(:post, "https://www.braintrust.dev/api/apikey/login")
        .to_return(status: 200, body: '{"ok":true}')

      env = {"HTTP_X_BT_AUTH_TOKEN" => "token"}
      @strategy.authenticate(env)

      assert_requested stub
    end
  end
end
