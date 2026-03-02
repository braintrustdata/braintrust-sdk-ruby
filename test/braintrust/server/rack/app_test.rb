# frozen_string_literal: true

require "test_helper"
require "braintrust/server"
require "rack/test"
require "json"

# Tests for the Rack app shell: health check, CORS, routing, and unknown routes.
# Endpoint-specific tests live in eval_endpoint_test.rb and list_endpoint_test.rb.
class Braintrust::Server::Rack::AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Braintrust::Server::Rack.app(evaluators: {}, auth: :none)
  end

  # --- Health Check ---

  def test_health_check_returns_ok
    get "/"

    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal "ok", body["status"]
  end

  def test_health_check_responds_to_get_only
    post "/"

    assert_equal 405, last_response.status
  end

  # --- CORS ---

  def test_cors_preflight_returns_204
    options "/", nil, {
      "HTTP_ORIGIN" => "https://www.braintrust.dev",
      "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "GET",
      "HTTP_ACCESS_CONTROL_REQUEST_HEADERS" => "authorization,content-type"
    }

    assert_equal 204, last_response.status
    assert_equal "https://www.braintrust.dev", last_response["Access-Control-Allow-Origin"]
    allowed = last_response["Access-Control-Allow-Headers"]
    assert_includes allowed, "authorization"
    assert_includes allowed, "content-type"
    assert_includes allowed, "x-bt-use-gateway"
    assert_equal "true", last_response["Access-Control-Allow-Credentials"]
  end

  def test_cors_preflight_private_network_access
    options "/", nil, {
      "HTTP_ORIGIN" => "https://www.braintrust.dev",
      "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "GET",
      "HTTP_ACCESS_CONTROL_REQUEST_PRIVATE_NETWORK" => "true"
    }

    assert_equal 204, last_response.status
    assert_equal "true", last_response["Access-Control-Allow-Private-Network"]
  end

  def test_cors_allows_preview_domains
    options "/", nil, {
      "HTTP_ORIGIN" => "https://my-branch.preview.braintrust.dev",
      "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "GET"
    }

    assert_equal 204, last_response.status
    assert_equal "https://my-branch.preview.braintrust.dev",
      last_response["Access-Control-Allow-Origin"]
  end

  def test_cors_headers_on_regular_response
    get "/", nil, {"HTTP_ORIGIN" => "https://www.braintrust.dev"}

    assert_equal "https://www.braintrust.dev", last_response["Access-Control-Allow-Origin"]
    assert_equal "true", last_response["Access-Control-Allow-Credentials"]
  end

  # --- Unknown routes ---

  def test_unknown_route_returns_404
    get "/nonexistent"
    assert_equal 404, last_response.status
  end
end
