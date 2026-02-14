# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Braintrust
  class API
    module Internal
      # Internal Experiments API
      # Not part of the public API - use through Eval.run
      class Experiments
        def initialize(state)
          @state = state
        end

        # Create an experiment
        # POST /v1/experiment
        # @param name [String] Experiment name
        # @param project_id [String] Project ID
        # @param ensure_new [Boolean] If true (default), fail if exists; if false, return existing
        # @param tags [Array<String>, nil] Optional tags
        # @param metadata [Hash, nil] Optional metadata
        # @return [Hash] Experiment data with "id", "name", "project_id", etc.
        def create(name:, project_id:, ensure_new: true, tags: nil, metadata: nil,
          dataset_id: nil, dataset_version: nil)
          uri = URI("#{@state.api_url}/v1/experiment")

          payload = {
            project_id: project_id,
            name: name,
            ensure_new: ensure_new
          }
          payload[:tags] = tags if tags
          payload[:metadata] = metadata if metadata
          payload[:dataset_id] = dataset_id if dataset_id
          payload[:dataset_version] = dataset_version if dataset_version

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request["Authorization"] = "Bearer #{@state.api_key}"
          request.body = JSON.dump(payload)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          response = http.request(request)

          unless response.is_a?(Net::HTTPSuccess)
            raise Error, "HTTP #{response.code} for POST #{uri}: #{response.body}"
          end

          JSON.parse(response.body)
        end
      end
    end
  end
end
