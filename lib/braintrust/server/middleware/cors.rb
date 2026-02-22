# frozen_string_literal: true

module Braintrust
  module Server
    module Middleware
      # CORS middleware allowing requests from *.braintrust.dev origins.
      # Handles preflight OPTIONS requests and adds CORS headers to all responses.
      class Cors
        ALLOWED_ORIGIN_PATTERN = /\Ahttps?:\/\/([\w-]+\.)*braintrust\.dev\z/

        HEADER_ALLOW_ORIGIN = "access-control-allow-origin"
        HEADER_ALLOW_CREDENTIALS = "access-control-allow-credentials"
        HEADER_ALLOW_METHODS = "access-control-allow-methods"
        HEADER_ALLOW_HEADERS = "access-control-allow-headers"
        HEADER_MAX_AGE = "access-control-max-age"
        HEADER_ALLOW_PRIVATE_NETWORK = "access-control-allow-private-network"
        HEADER_EXPOSE_HEADERS = "access-control-expose-headers"
        EXPOSED_HEADERS = "x-bt-cursor, x-bt-found-existing-experiment, x-bt-span-id, x-bt-span-export"

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
          headers[HEADER_ALLOW_METHODS] = "GET, POST, OPTIONS"
          headers[HEADER_ALLOW_HEADERS] = env.fetch("HTTP_ACCESS_CONTROL_REQUEST_HEADERS", "")
          headers[HEADER_MAX_AGE] = "86400"

          if env["HTTP_ACCESS_CONTROL_REQUEST_PRIVATE_NETWORK"] == "true"
            headers[HEADER_ALLOW_PRIVATE_NETWORK] = "true"
          end

          [204, headers, []]
        end

        def add_cors_headers(headers, origin)
          return unless origin && allowed_origin?(origin)

          headers[HEADER_ALLOW_ORIGIN] = origin
          headers[HEADER_ALLOW_CREDENTIALS] = "true"
          headers[HEADER_EXPOSE_HEADERS] = EXPOSED_HEADERS
        end

        def allowed_origin?(origin)
          ALLOWED_ORIGIN_PATTERN.match?(origin)
        end
      end
    end
  end
end
