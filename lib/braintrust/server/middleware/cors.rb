# frozen_string_literal: true

module Braintrust
  module Server
    module Middleware
      # CORS middleware allowing requests from *.braintrust.dev origins.
      # Handles preflight OPTIONS requests and adds CORS headers to all responses.
      class Cors
        ALLOWED_ORIGIN_PATTERN = /\Ahttps?:\/\/([\w-]+\.)*braintrust\.dev\z/

        def initialize(app)
          @app = app
        end

        def call(env)
          origin = env["HTTP_ORIGIN"]

          if env["REQUEST_METHOD"] == "OPTIONS"
            return handle_preflight(env, origin)
          end

          status, headers, body = @app.call(env)
          add_cors_headers(headers, origin)
          [status, headers, body]
        end

        private

        def handle_preflight(env, origin)
          headers = {}
          add_cors_headers(headers, origin)
          headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
          headers["Access-Control-Allow-Headers"] = "Content-Type, X-Bt-Auth-Token"
          headers["Access-Control-Max-Age"] = "86400"

          if env["HTTP_ACCESS_CONTROL_REQUEST_PRIVATE_NETWORK"] == "true"
            headers["Access-Control-Allow-Private-Network"] = "true"
          end

          [204, headers, []]
        end

        def add_cors_headers(headers, origin)
          return unless origin && allowed_origin?(origin)

          headers["Access-Control-Allow-Origin"] = origin
          headers["Access-Control-Allow-Credentials"] = "true"
        end

        def allowed_origin?(origin)
          ALLOWED_ORIGIN_PATTERN.match?(origin)
        end
      end
    end
  end
end
