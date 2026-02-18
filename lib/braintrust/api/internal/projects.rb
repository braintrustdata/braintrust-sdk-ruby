# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../../internal/http"

module Braintrust
  class API
    module Internal
      # Internal Projects API
      # Not part of the public API - use through Eval.run
      class Projects
        def initialize(state)
          @state = state
        end

        # Create or get a project by name (idempotent)
        # POST /v1/project
        # @param name [String] Project name
        # @return [Hash] Project data with "id", "name", "org_id", etc.
        def create(name:)
          uri = URI("#{@state.api_url}/v1/project")

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request["Authorization"] = "Bearer #{@state.api_key}"
          request.body = JSON.dump({name: name})

          response = Braintrust::Internal::Http.with_redirects(uri, request)

          unless response.is_a?(Net::HTTPSuccess)
            raise Error, "HTTP #{response.code} for POST #{uri}: #{response.body}"
          end

          JSON.parse(response.body)
        end
      end
    end
  end
end
