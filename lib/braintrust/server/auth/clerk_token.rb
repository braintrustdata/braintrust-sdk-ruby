# frozen_string_literal: true

require "net/http"
require "json"

module Braintrust
  module Server
    module Auth
      # Validates Clerk JWT session tokens via the Braintrust app endpoint.
      # The browser forwards the Clerk session token which is validated by
      # POST /api/apikey/login on the app server.
      class ClerkToken
        DEFAULT_APP_URL = "https://www.braintrust.dev"
        RACK_AUTH_HEADER = "HTTP_AUTHORIZATION"
        RACK_ORG_NAME_HEADER = "HTTP_X_BT_ORG_NAME"
        BEARER_PATTERN = /\ABearer (.+)\z/
        LOGIN_PATH = "/api/apikey/login"

        def initialize(app_url: nil)
          @app_url = app_url || DEFAULT_APP_URL
        end

        def authenticate(env)
          token = extract_bearer_token(env)
          return nil unless token

          login_response = validate_token(token)
          return nil unless login_response

          org_name = env[RACK_ORG_NAME_HEADER]

          {
            "api_key" => token,
            "org_id" => login_response["org_id"],
            "org_name" => org_name || login_response["org_name"],
            "app_url" => @app_url,
            "api_url" => login_response["api_url"] || @app_url
          }
        end

        private

        def extract_bearer_token(env)
          header = env[RACK_AUTH_HEADER]
          return nil unless header
          header[BEARER_PATTERN, 1]
        end

        def validate_token(token)
          uri = URI("#{@app_url}#{LOGIN_PATH}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request.body = JSON.dump({token: token})

          response = http.request(request)
          return nil unless response.code == "200"

          JSON.parse(response.body)
        rescue StandardError
          nil
        end
      end
    end
  end
end
