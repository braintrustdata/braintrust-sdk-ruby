# frozen_string_literal: true

require "test_helper"
require "braintrust/server"

class Braintrust::Server::Middleware::CorsTest < Minitest::Test
  Cors = Braintrust::Server::Middleware::Cors

  def setup
    @inner_app = ->(env) { [200, {"content-type" => "application/json"}, ["ok"]] }
    @cors = Cors.new(@inner_app)
  end

  # --- Preflight (OPTIONS) ---

  def test_preflight_returns_204
    env = preflight_env("https://www.braintrust.dev")
    status, _, _ = @cors.call(env)

    assert_equal 204, status
  end

  def test_preflight_sets_allow_origin
    env = preflight_env("https://www.braintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_equal "https://www.braintrust.dev", headers[Cors::HEADER_ALLOW_ORIGIN]
  end

  def test_preflight_sets_allow_credentials
    env = preflight_env("https://www.braintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_equal "true", headers[Cors::HEADER_ALLOW_CREDENTIALS]
  end

  def test_preflight_sets_allow_methods
    env = preflight_env("https://www.braintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_includes headers[Cors::HEADER_ALLOW_METHODS], "POST"
    assert_includes headers[Cors::HEADER_ALLOW_METHODS], "GET"
  end

  def test_preflight_echoes_requested_headers
    env = preflight_env("https://www.braintrust.dev")
    env["HTTP_ACCESS_CONTROL_REQUEST_HEADERS"] = "authorization,content-type,x-bt-org-name"
    _, headers, _ = @cors.call(env)

    assert_equal "authorization,content-type,x-bt-org-name", headers[Cors::HEADER_ALLOW_HEADERS]
  end

  def test_preflight_returns_empty_allow_headers_when_none_requested
    env = preflight_env("https://www.braintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_equal "", headers[Cors::HEADER_ALLOW_HEADERS]
  end

  def test_preflight_sets_max_age
    env = preflight_env("https://www.braintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_equal "86400", headers[Cors::HEADER_MAX_AGE]
  end

  def test_preflight_private_network_access
    env = preflight_env("https://www.braintrust.dev")
    env["HTTP_ACCESS_CONTROL_REQUEST_PRIVATE_NETWORK"] = "true"
    _, headers, _ = @cors.call(env)

    assert_equal "true", headers[Cors::HEADER_ALLOW_PRIVATE_NETWORK]
  end

  def test_preflight_no_private_network_when_not_requested
    env = preflight_env("https://www.braintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_nil headers[Cors::HEADER_ALLOW_PRIVATE_NETWORK]
  end

  def test_preflight_does_not_call_inner_app
    called = false
    inner = ->(_env) {
      called = true
      [200, {}, []]
    }
    cors = Cors.new(inner)

    cors.call(preflight_env("https://www.braintrust.dev"))

    refute called, "Inner app should not be called for preflight"
  end

  # --- Origin validation ---

  def test_allows_www_braintrust_dev
    env = get_env("https://www.braintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_equal "https://www.braintrust.dev", headers[Cors::HEADER_ALLOW_ORIGIN]
  end

  def test_allows_bare_braintrust_dev
    env = get_env("https://braintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_equal "https://braintrust.dev", headers[Cors::HEADER_ALLOW_ORIGIN]
  end

  def test_allows_preview_subdomain
    env = get_env("https://my-branch.preview.braintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_equal "https://my-branch.preview.braintrust.dev",
      headers[Cors::HEADER_ALLOW_ORIGIN]
  end

  def test_allows_deep_subdomain
    env = get_env("https://a.b.c.braintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_equal "https://a.b.c.braintrust.dev", headers[Cors::HEADER_ALLOW_ORIGIN]
  end

  def test_rejects_unknown_origin
    env = get_env("https://evil.com")
    _, headers, _ = @cors.call(env)

    assert_nil headers[Cors::HEADER_ALLOW_ORIGIN]
  end

  def test_rejects_origin_suffix_attack
    env = get_env("https://notbraintrust.dev")
    _, headers, _ = @cors.call(env)

    assert_nil headers[Cors::HEADER_ALLOW_ORIGIN]
  end

  def test_no_cors_headers_without_origin
    env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/"}
    _, headers, _ = @cors.call(env)

    assert_nil headers[Cors::HEADER_ALLOW_ORIGIN]
  end

  # --- Regular response passthrough ---

  def test_passes_through_inner_app_status
    inner = ->(_env) { [418, {}, ["teapot"]] }
    cors = Cors.new(inner)

    status, _, _ = cors.call(get_env("https://www.braintrust.dev"))

    assert_equal 418, status
  end

  def test_passes_through_inner_app_body
    inner = ->(_env) { [200, {}, ["response body"]] }
    cors = Cors.new(inner)

    _, _, body = cors.call(get_env("https://www.braintrust.dev"))

    assert_equal ["response body"], body
  end

  def test_merges_cors_headers_with_inner_headers
    inner = ->(_env) { [200, {"x-custom" => "value"}, []] }
    cors = Cors.new(inner)

    _, headers, _ = cors.call(get_env("https://www.braintrust.dev"))

    assert_equal "value", headers["x-custom"]
    assert_equal "https://www.braintrust.dev", headers[Cors::HEADER_ALLOW_ORIGIN]
  end

  private

  def preflight_env(origin)
    {
      "REQUEST_METHOD" => "OPTIONS",
      "PATH_INFO" => "/eval",
      "HTTP_ORIGIN" => origin,
      "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "POST"
    }
  end

  def get_env(origin)
    {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/",
      "HTTP_ORIGIN" => origin
    }
  end
end
