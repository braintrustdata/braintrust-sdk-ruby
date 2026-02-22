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
        def initialize(app_url: nil)
          @app_url = app_url || "https://www.braintrust.dev"
        end

        def authenticate(env)
          token = env["HTTP_X_BT_AUTH_TOKEN"]
          return nil unless token

          validate_token(token)
        end

        private

        def validate_token(token)
          uri = URI("#{@app_url}/api/apikey/login")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request.body = JSON.dump({token: token})

          response = http.request(request)
          return nil unless response.code == "200"

          JSON.parse(response.body)
        rescue
          nil
        end
      end
    end
  end
end
