# frozen_string_literal: true

require "test_helper"
require "braintrust/server"

# Tests for the Braintrust::Server::Rack entry point.
# This is the primary public interface for customers to create a server.
class Braintrust::Server::RackTest < Minitest::Test
  def test_app_returns_cors_wrapping_auth_wrapping_router
    app = Braintrust::Server::Rack.app(evaluators: {}, auth: :none)

    assert_instance_of Braintrust::Server::Middleware::Cors, app

    auth_middleware = app.instance_variable_get(:@app)
    assert_instance_of Braintrust::Server::Middleware::Auth, auth_middleware

    router = auth_middleware.instance_variable_get(:@app)
    assert_instance_of Braintrust::Server::Router, router
  end

  def test_app_uses_no_auth_strategy_when_none
    app = Braintrust::Server::Rack.app(evaluators: {}, auth: :none)

    auth_middleware = app.instance_variable_get(:@app)
    strategy = auth_middleware.instance_variable_get(:@strategy)

    assert_instance_of Braintrust::Server::Auth::NoAuth, strategy
  end

  def test_app_uses_clerk_token_strategy_by_default
    app = Braintrust::Server::Rack.app(evaluators: {})

    auth_middleware = app.instance_variable_get(:@app)
    strategy = auth_middleware.instance_variable_get(:@strategy)

    assert_instance_of Braintrust::Server::Auth::ClerkToken, strategy
  end

  def test_app_accepts_custom_auth_strategy
    custom_auth = Braintrust::Server::Auth::NoAuth.new

    app = Braintrust::Server::Rack.app(evaluators: {}, auth: custom_auth)

    auth_middleware = app.instance_variable_get(:@app)
    strategy = auth_middleware.instance_variable_get(:@strategy)

    assert_same custom_auth, strategy
  end

  def test_app_registers_evaluators_on_router
    evaluator = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

    app = Braintrust::Server::Rack.app(
      evaluators: {"my-eval" => evaluator},
      auth: :none
    )

    auth_middleware = app.instance_variable_get(:@app)
    router = auth_middleware.instance_variable_get(:@app)
    routes = router.instance_variable_get(:@routes)

    # The router should have routes for health, list, and eval
    assert routes.key?("GET /"), "Expected GET / route"
    assert routes.key?("POST /list"), "Expected POST /list route"
    assert routes.key?("POST /eval"), "Expected POST /eval route"

    # The eval handler should have our evaluator
    eval_handler = routes["POST /eval"]
    handler_evaluators = eval_handler.instance_variable_get(:@evaluators)
    assert_same evaluator, handler_evaluators["my-eval"]
  end
end
