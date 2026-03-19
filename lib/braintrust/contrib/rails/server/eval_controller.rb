# frozen_string_literal: true

module Braintrust
  module Contrib
    module Rails
      module Server
        class EvalController < ApplicationController
          include ActionController::Live

          def create
            body = parse_json_body
            unless body
              render json: {"error" => "Invalid JSON body"}, status: :bad_request
              return
            end

            result = Engine.eval_service.validate(body)
            if result[:error]
              render json: {"error" => result[:error]}, status: result[:status]
              return
            end

            response.headers["Content-Type"] = "text/event-stream"
            response.headers["Cache-Control"] = "no-cache"
            response.headers["Connection"] = "keep-alive"

            sse = Braintrust::Server::SSEWriter.new { |chunk| response.stream.write(chunk) }
            Engine.eval_service.stream(result, auth: @braintrust_auth, sse: sse)
          ensure
            response.stream.close
          end
        end
      end
    end
  end
end
