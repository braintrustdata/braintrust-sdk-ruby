# frozen_string_literal: true

require "test_helper"
require "braintrust/server"
require "json"

class Braintrust::Server::Middleware::AuthTest < Minitest::Test
  def test_passes_through_when_auth_succeeds
    strategy = FakeAuth.new(result: {api_key: "key-123"})
    inner = ->(_env) { [200, {}, ["ok"]] }
    auth = Braintrust::Server::Middleware::Auth.new(inner, strategy: strategy)

    status, _, body = auth.call({})

    assert_equal 200, status
    assert_equal ["ok"], body
  end

  def test_returns_401_when_auth_fails
    strategy = FakeAuth.new(result: nil)
    inner = ->(_env) { [200, {}, ["ok"]] }
    auth = Braintrust::Server::Middleware::Auth.new(inner, strategy: strategy)

    status, _, body = auth.call({})

    assert_equal 401, status
    parsed = JSON.parse(body.first)
    assert_match(/unauthorized/i, parsed["error"])
  end

  def test_sets_auth_result_in_env
    strategy = FakeAuth.new(result: {api_key: "key-123"})
    received_env = nil
    inner = ->(env) {
      received_env = env
      [200, {}, []]
    }
    auth = Braintrust::Server::Middleware::Auth.new(inner, strategy: strategy)

    auth.call({})

    assert_equal({api_key: "key-123"}, received_env["braintrust.auth"])
  end

  def test_does_not_call_inner_when_auth_fails
    strategy = FakeAuth.new(result: nil)
    called = false
    inner = ->(_env) {
      called = true
      [200, {}, []]
    }
    auth = Braintrust::Server::Middleware::Auth.new(inner, strategy: strategy)

    auth.call({})

    refute called, "Inner app should not be called when auth fails"
  end

  def test_passes_env_to_strategy
    received_env = nil
    strategy = FakeAuth.new(result: true) { |env| received_env = env }
    inner = ->(_env) { [200, {}, []] }
    auth = Braintrust::Server::Middleware::Auth.new(inner, strategy: strategy)

    env = {"HTTP_AUTHORIZATION" => "Bearer my-token"}
    auth.call(env)

    assert_equal "Bearer my-token", received_env["HTTP_AUTHORIZATION"]
  end

  def test_no_auth_strategy_always_passes
    strategy = Braintrust::Server::Auth::NoAuth.new
    inner = ->(_env) { [200, {}, ["ok"]] }
    auth = Braintrust::Server::Middleware::Auth.new(inner, strategy: strategy)

    status, _, _ = auth.call({})

    assert_equal 200, status
  end

  private

  class FakeAuth
    def initialize(result:, &on_authenticate)
      @result = result
      @on_authenticate = on_authenticate
    end

    def authenticate(env)
      @on_authenticate&.call(env)
      @result
    end
  end
end
