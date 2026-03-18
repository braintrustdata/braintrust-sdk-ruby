# frozen_string_literal: true

module Braintrust
  module Contrib
    module Rails
      class ApplicationController < ActionController::API
        before_action :authenticate!

        private

        def authenticate!
          auth_result = Engine.auth_strategy.authenticate(request.env)
          unless auth_result
            render json: {"error" => "Unauthorized"}, status: :unauthorized
            return
          end

          request.env["braintrust.auth"] = auth_result
          @braintrust_auth = auth_result
        end

        def parse_json_body
          body = request.body.read
          return nil if body.nil? || body.empty?
          JSON.parse(body)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
