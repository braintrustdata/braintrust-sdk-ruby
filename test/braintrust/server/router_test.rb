# frozen_string_literal: true

require "test_helper"
require "braintrust/server"
require "json"

class Braintrust::Server::RouterTest < Minitest::Test
  def setup
    @router = Braintrust::Server::Router.new
  end

  def test_dispatches_to_matching_handler
    handler = ->(env) { [200, {}, ["ok"]] }
    @router.add("GET", "/health", handler)

    status, _, body = @router.call(rack_env("GET", "/health"))

    assert_equal 200, status
    assert_equal ["ok"], body
  end

  def test_returns_404_for_unknown_path
    status, _, body = @router.call(rack_env("GET", "/unknown"))

    assert_equal 404, status
    parsed = JSON.parse(body.first)
    assert_match(/not found/i, parsed["error"])
  end

  def test_returns_405_for_wrong_method
    handler = ->(env) { [200, {}, ["ok"]] }
    @router.add("POST", "/data", handler)

    status, _, body = @router.call(rack_env("GET", "/data"))

    assert_equal 405, status
    parsed = JSON.parse(body.first)
    assert_match(/method not allowed/i, parsed["error"])
  end

  def test_multiple_routes
    @router.add("GET", "/a", ->(env) { [200, {}, ["a"]] })
    @router.add("POST", "/b", ->(env) { [201, {}, ["b"]] })

    status_a, _, body_a = @router.call(rack_env("GET", "/a"))
    status_b, _, body_b = @router.call(rack_env("POST", "/b"))

    assert_equal 200, status_a
    assert_equal ["a"], body_a
    assert_equal 201, status_b
    assert_equal ["b"], body_b
  end

  def test_same_path_different_methods
    @router.add("GET", "/resource", ->(env) { [200, {}, ["get"]] })
    @router.add("POST", "/resource", ->(env) { [201, {}, ["post"]] })

    _, _, get_body = @router.call(rack_env("GET", "/resource"))
    _, _, post_body = @router.call(rack_env("POST", "/resource"))

    assert_equal ["get"], get_body
    assert_equal ["post"], post_body
  end

  def test_add_returns_self_for_chaining
    result = @router.add("GET", "/", ->(env) { [200, {}, []] })
    assert_same @router, result
  end

  def test_passes_env_to_handler
    received_env = nil
    handler = ->(env) {
      received_env = env
      [200, {}, []]
    }
    @router.add("GET", "/test", handler)

    env = rack_env("GET", "/test")
    env["HTTP_X_CUSTOM"] = "value"
    @router.call(env)

    assert_equal "value", received_env["HTTP_X_CUSTOM"]
  end

  private

  def rack_env(method, path)
    {"REQUEST_METHOD" => method, "PATH_INFO" => path}
  end
end
