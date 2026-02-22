# frozen_string_literal: true

require "json"

module Braintrust
  module Server
    module Middleware
      # Auth middleware that validates requests using a pluggable strategy.
      # Sets env["braintrust.auth"] with the authentication result on success.
      class Auth
        def initialize(app, strategy:)
          @app = app
          @strategy = strategy
        end

        def call(env)
          auth_result = @strategy.authenticate(env)
          unless auth_result
            return [401, {"content-type" => "application/json"},
              [JSON.dump({"error" => "Unauthorized"})]]
          end

          env["braintrust.auth"] = auth_result
          @app.call(env)
        end
      end
    end
  end
end
