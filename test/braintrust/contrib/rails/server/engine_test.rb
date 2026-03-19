# frozen_string_literal: true

require "test_helper"
require_relative "../rails_server_helper"

module Braintrust
  module Contrib
    module Rails
      module Server
        class EngineTest < Minitest::Test
          include Braintrust::Contrib::Rails::ServerHelper

          def setup
            skip_unless_rails_server!
            reset_engine!
          end

          def test_evaluators_returns_config_value
            evaluator = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
            Engine.config.evaluators = {"my-eval" => evaluator}
            assert_same evaluator, Engine.evaluators["my-eval"]
          end

          def test_auth_strategy_returns_no_auth_for_none
            Engine.config.auth = :none
            assert_instance_of Braintrust::Server::Auth::NoAuth, Engine.auth_strategy
          end

          def test_auth_strategy_returns_clerk_token_by_default
            Engine.config.auth = :clerk_token
            assert_instance_of Braintrust::Server::Auth::ClerkToken, Engine.auth_strategy
          end

          def test_auth_strategy_accepts_custom_object
            custom = Braintrust::Server::Auth::NoAuth.new
            Engine.config.auth = custom
            assert_same custom, Engine.auth_strategy
          end

          def test_auth_strategy_raises_for_unknown_symbol
            Engine.config.auth = :jwt
            assert_raises(ArgumentError) { Engine.auth_strategy }
          end

          def test_auth_strategy_raises_for_unknown_string
            Engine.config.auth = "jwt"
            assert_raises(ArgumentError) { Engine.auth_strategy }
          end

          def test_auth_strategy_reflects_config_changes_without_manual_reset
            Engine.config.auth = :none
            assert_instance_of Braintrust::Server::Auth::NoAuth, Engine.auth_strategy

            Engine.config.auth = :clerk_token
            assert_instance_of Braintrust::Server::Auth::ClerkToken, Engine.auth_strategy
          end

          def test_list_service_uses_latest_evaluators_without_manual_reset
            first = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
            second = Braintrust::Eval::Evaluator.new(task: ->(input) { input })

            Engine.config.evaluators = {"first" => first}
            assert_equal ["first"], Engine.list_service.call.keys

            Engine.config.evaluators = {"second" => second}
            assert_equal ["second"], Engine.list_service.call.keys
          end

          def test_eval_service_uses_latest_evaluators_without_manual_reset
            first = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
            second = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
            payload = {"data" => {"data" => [{"input" => "hello"}]}}

            Engine.config.evaluators = {"first" => first}
            service = Engine.eval_service
            assert_same first, service.validate(payload.merge("name" => "first"))[:evaluator]

            Engine.config.evaluators = {"second" => second}
            assert_same second, service.validate(payload.merge("name" => "second"))[:evaluator]
          end

          def test_eval_service_returns_eval_instance
            assert_instance_of Braintrust::Server::Services::Eval, Engine.eval_service
          end

          def test_list_service_returns_list_instance
            assert_instance_of Braintrust::Server::Services::List, Engine.list_service
          end

          def test_eval_service_is_memoized
            svc1 = Engine.eval_service
            svc2 = Engine.eval_service
            assert_same svc1, svc2
          end

          def test_configure_yields_config_without_resetting_eval_service
            svc_before = Engine.eval_service
            evaluator = Braintrust::Eval::Evaluator.new(task: ->(input) { input })
            payload = {"name" => "configured-eval", "data" => {"data" => [{"input" => "hello"}]}}

            Engine.configure do |config|
              config.evaluators = {"configured-eval" => evaluator}
              config.auth = :none
            end

            assert_same evaluator, Engine.evaluators["configured-eval"]
            assert_instance_of Braintrust::Server::Auth::NoAuth, Engine.auth_strategy
            assert_same svc_before, Engine.eval_service
            assert_same evaluator, Engine.eval_service.validate(payload)[:evaluator]
          end

          def test_cors_middleware_is_in_middleware_stack
            stack = BraintrustRailsTestApp.middleware
            middleware_classes = stack.map { |m|
              begin
                m.klass
              rescue
                m
              end
            }
            assert middleware_classes.any? { |klass|
              klass == Braintrust::Server::Middleware::Cors
            }, "CORS middleware should be in the stack"
          end

          def test_engine_has_expected_routes
            routes = Engine.routes.routes.map { |r| "#{r.verb} #{r.path.spec}" }
            assert routes.any? { |r| r.include?("/list") }, "Should have /list route"
            assert routes.any? { |r| r.include?("/eval") }, "Should have /eval route"
          end
        end
      end
    end
  end
end
