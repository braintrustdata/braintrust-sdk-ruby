# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../logger"

module Braintrust
  class API
    # Experiments API namespace
    # Provides methods for fetching experiment comparison data
    class Experiments
      def initialize(api)
        @api = api
        @state = api.state
      end

      # Fetch experiment comparison data
      # GET /experiment-comparison2
      # Returns score and metric summaries with comparison to baseline experiment
      # @param experiment_id [String] Current experiment ID
      # @param base_experiment_id [String, nil] Baseline experiment ID to compare against.
      #   If nil, API will auto-select based on experiment metadata or most recent experiment.
      # @return [Hash] Response with scores, metrics, and comparison info
      #   - "scores" [Hash] Score summaries keyed by name
      #   - "metrics" [Hash] Metric summaries keyed by name
      #   - "comparisonExperimentName" [String, nil] Name of baseline experiment
      #   - "comparisonExperimentId" [String, nil] ID of baseline experiment
      def comparison(experiment_id:, base_experiment_id: nil)
        params = {"experiment_id" => experiment_id}
        params["base_experiment_id"] = base_experiment_id if base_experiment_id

        http_get("/experiment-comparison2", params)
      end

      private

      # Core HTTP request method with logging
      # @param method [Symbol] :get or :post
      # @param path [String] API path
      # @param params [Hash] Query params (for GET)
      # @param payload [Hash, nil] JSON payload (for POST)
      # @return [Hash] Parsed JSON response
      def http_request(method, path, params: {}, payload: nil)
        # Build URI - use api_url for this endpoint
        base = @state.api_url || "https://api.braintrust.dev"
        uri = URI("#{base}#{path}")
        uri.query = URI.encode_www_form(params) unless params.empty?

        # Create request
        request = case method
        when :get
          Net::HTTP::Get.new(uri)
        when :post
          req = Net::HTTP::Post.new(uri)
          req["Content-Type"] = "application/json"
          req.body = JSON.dump(payload) if payload
          req
        else
          raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

        # Use Bearer token format for API endpoints
        request["Authorization"] = "Bearer #{@state.api_key}"

        # Execute request with timing
        start_time = Time.now
        Log.debug("[API] #{method.upcase} #{uri}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        response = http.request(request)

        duration_ms = ((Time.now - start_time) * 1000).round(2)
        Log.debug("[API] #{method.upcase} #{uri} -> #{response.code} (#{duration_ms}ms, #{response.body.bytesize} bytes)")

        # Handle response
        unless response.is_a?(Net::HTTPSuccess)
          Log.debug("[API] Error response body: #{response.body}")
          raise Error, "HTTP #{response.code} for #{method.upcase} #{uri}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      # HTTP GET with query params - returns parsed JSON
      def http_get(path, params = {})
        http_request(:get, path, params: params)
      end
    end
  end
end
