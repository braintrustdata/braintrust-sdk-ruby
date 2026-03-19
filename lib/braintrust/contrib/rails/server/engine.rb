# frozen_string_literal: true

module Braintrust
  module Contrib
    module Rails
      module Server
        class Engine < ::Rails::Engine
          isolate_namespace Braintrust::Contrib::Rails::Server

          config.evaluators = {}
          config.auth = :clerk_token

          # Register the engine's routes file so Rails loads it during initialization.
          paths["config/routes.rb"] << File.expand_path("routes.rb", __dir__)

          initializer "braintrust.server.cors" do |app|
            app.middleware.use Braintrust::Server::Middleware::Cors
          end

          # Class-level helpers that read from engine config.

          def self.evaluators
            config.evaluators
          end

          def self.auth_strategy
            resolve_auth(config.auth)
          end

          def self.list_service
            Braintrust::Server::Services::List.new(-> { config.evaluators })
          end

          # Long-lived so the state cache persists across requests.
          def self.eval_service
            @eval_service ||= Braintrust::Server::Services::Eval.new(-> { config.evaluators })
          end

          # Support the explicit `|config|` style used by this integration while
          # still delegating zero-arity DSL blocks to Rails' native implementation.
          def self.configure(&block)
            return super if block&.arity == 0
            yield config if block
          end

          def self.resolve_auth(auth)
            case auth
            when :none
              Braintrust::Server::Auth::NoAuth.new
            when :clerk_token
              Braintrust::Server::Auth::ClerkToken.new
            when Symbol, String
              raise ArgumentError, "Unknown auth strategy #{auth.inspect}. Expected :none, :clerk_token, or an auth object."
            else
              auth
            end
          end
          private_class_method :resolve_auth

          generators do
            require "braintrust/contrib/rails/server/generator"
          end
        end
      end
    end
  end
end

require_relative "application_controller"
require_relative "health_controller"
require_relative "list_controller"
require_relative "eval_controller"
