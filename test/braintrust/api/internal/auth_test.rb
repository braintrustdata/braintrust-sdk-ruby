# frozen_string_literal: true

require "test_helper"
require "braintrust/api/internal/auth"

class Braintrust::API::Internal::AuthTest < Minitest::Test
  def test_mask_api_key_with_nil
    assert_equal "nil", Braintrust::API::Internal::Auth.mask_api_key(nil)
  end

  def test_mask_api_key_short
    assert_equal "short", Braintrust::API::Internal::Auth.mask_api_key("short")
  end

  def test_mask_api_key_long
    assert_equal "12345678...abcd", Braintrust::API::Internal::Auth.mask_api_key("1234567890abcdefghijklmnopqrstuvwxyzabcd")
  end

  def test_login_with_test_api_key
    result = Braintrust::API::Internal::Auth.login(
      api_key: "test-api-key",
      app_url: "https://www.braintrust.dev"
    )

    assert_equal "test-org-id", result.org_id
    assert_equal "test-org", result.org_name
    assert_equal "https://api.ruby-sdk-fixture.com", result.api_url
    assert_equal "https://proxy.ruby-sdk-fixture.com", result.proxy_url
  end

  def test_login_with_test_api_key_and_org_name
    result = Braintrust::API::Internal::Auth.login(
      api_key: "test-api-key",
      app_url: "https://www.braintrust.dev",
      org_name: "custom-org"
    )

    assert_equal "custom-org", result.org_name
  end

  def test_login_bad_request
    stub = stub_request(:post, "https://www.braintrust.dev/api/apikey/login")
      .to_return(status: 400, body: "Invalid request format")

    error = assert_raises(Braintrust::Error) do
      Braintrust::API::Internal::Auth.login(
        api_key: "real-key",
        app_url: "https://www.braintrust.dev"
      )
    end

    assert_match(/bad request/i, error.message)
    assert_match(/400/, error.message)
  ensure
    remove_request_stub(stub)
  end

  def test_login_client_error
    stub = stub_request(:post, "https://www.braintrust.dev/api/apikey/login")
      .to_return(status: 404, body: "", headers: {})

    error = assert_raises(Braintrust::Error) do
      Braintrust::API::Internal::Auth.login(
        api_key: "real-key",
        app_url: "https://www.braintrust.dev"
      )
    end

    assert_match(/client error/i, error.message)
    assert_match(/404/, error.message)
  ensure
    remove_request_stub(stub)
  end

  def test_login_server_error
    stub = stub_request(:post, "https://www.braintrust.dev/api/apikey/login")
      .to_return(status: 500, body: "", headers: {})

    error = assert_raises(Braintrust::Error) do
      Braintrust::API::Internal::Auth.login(
        api_key: "real-key",
        app_url: "https://www.braintrust.dev"
      )
    end

    assert_match(/server error/i, error.message)
    assert_match(/500/, error.message)
  ensure
    remove_request_stub(stub)
  end

  def test_login_unexpected_response
    stub = stub_request(:post, "https://www.braintrust.dev/api/apikey/login")
      .to_return(status: 301, body: "", headers: {})

    error = assert_raises(Braintrust::Error) do
      Braintrust::API::Internal::Auth.login(
        api_key: "real-key",
        app_url: "https://www.braintrust.dev"
      )
    end

    assert_match(/unexpected response/i, error.message)
    assert_match(/301/, error.message)
  ensure
    remove_request_stub(stub)
  end

  def test_login_no_organizations
    stub = stub_request(:post, "https://www.braintrust.dev/api/apikey/login")
      .to_return(
        status: 200,
        body: JSON.generate({org_info: []}),
        headers: {"Content-Type" => "application/json"}
      )

    error = assert_raises(Braintrust::Error) do
      Braintrust::API::Internal::Auth.login(
        api_key: "real-key",
        app_url: "https://www.braintrust.dev"
      )
    end

    assert_match(/no organizations found/i, error.message)
  ensure
    remove_request_stub(stub)
  end

  def test_login_org_name_not_found
    stub = stub_request(:post, "https://www.braintrust.dev/api/apikey/login")
      .to_return(
        status: 200,
        body: JSON.generate({
          org_info: [
            {
              id: "org1",
              name: "first-org",
              api_url: "https://api.braintrust.dev",
              proxy_url: "https://api.braintrust.dev"
            },
            {
              id: "org2",
              name: "second-org",
              api_url: "https://api.braintrust.dev",
              proxy_url: "https://api.braintrust.dev"
            }
          ]
        }),
        headers: {"Content-Type" => "application/json"}
      )

    error = assert_raises(Braintrust::Error) do
      Braintrust::API::Internal::Auth.login(
        api_key: "real-key",
        app_url: "https://www.braintrust.dev",
        org_name: "nonexistent-org"
      )
    end

    assert_match(/organization 'nonexistent-org' not found/i, error.message)
    assert_match(/first-org, second-org/, error.message)
  ensure
    remove_request_stub(stub)
  end

  def test_login_selects_first_org_when_no_org_name
    stub = stub_request(:post, "https://www.braintrust.dev/api/apikey/login")
      .to_return(
        status: 200,
        body: JSON.generate({
          org_info: [
            {
              id: "first-id",
              name: "first-org",
              api_url: "https://api1.braintrust.dev",
              proxy_url: "https://proxy1.braintrust.dev"
            },
            {
              id: "second-id",
              name: "second-org",
              api_url: "https://api2.braintrust.dev",
              proxy_url: "https://proxy2.braintrust.dev"
            }
          ]
        }),
        headers: {"Content-Type" => "application/json"}
      )

    result = Braintrust::API::Internal::Auth.login(
      api_key: "real-key",
      app_url: "https://www.braintrust.dev"
    )

    assert_equal "first-id", result.org_id
    assert_equal "first-org", result.org_name
    assert_equal "https://api1.braintrust.dev", result.api_url
    assert_equal "https://proxy1.braintrust.dev", result.proxy_url
  ensure
    remove_request_stub(stub)
  end

  def test_login_selects_matching_org_when_org_name_provided
    stub = stub_request(:post, "https://www.braintrust.dev/api/apikey/login")
      .to_return(
        status: 200,
        body: JSON.generate({
          org_info: [
            {
              id: "first-id",
              name: "first-org",
              api_url: "https://api1.braintrust.dev",
              proxy_url: "https://proxy1.braintrust.dev"
            },
            {
              id: "second-id",
              name: "second-org",
              api_url: "https://api2.braintrust.dev",
              proxy_url: "https://proxy2.braintrust.dev"
            }
          ]
        }),
        headers: {"Content-Type" => "application/json"}
      )

    result = Braintrust::API::Internal::Auth.login(
      api_key: "real-key",
      app_url: "https://www.braintrust.dev",
      org_name: "second-org"
    )

    assert_equal "second-id", result.org_id
    assert_equal "second-org", result.org_name
    assert_equal "https://api2.braintrust.dev", result.api_url
    assert_equal "https://proxy2.braintrust.dev", result.proxy_url
  ensure
    remove_request_stub(stub)
  end
end
