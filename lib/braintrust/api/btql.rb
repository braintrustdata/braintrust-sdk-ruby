# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../logger"

module Braintrust
  class API
    # BTQL API namespace
    # Provides methods for querying spans and other data using BTQL
    class BTQL
      def initialize(api)
        @api = api
        @state = api.state
      end

      # Query spans using BTQL
      # POST /btql
      # @param query [Hash] AST-based query filter
      # @param object_type [String] Type of object (e.g., "experiment")
      # @param object_id [String] Object ID
      # @param fmt [String] Response format (default: "jsonl")
      # @return [Hash] Response with :body, :freshness_state
      def query(query:, object_type:, object_id:, fmt: "jsonl")
        payload = {
          query: query,
          object_type: object_type,
          object_id: object_id,
          fmt: fmt
        }

        response = http_post_json_raw("/btql", payload)

        {
          body: response.body,
          freshness_state: response["x-bt-freshness-state"] || "complete"
        }
      end

      private

      # Core HTTP request method (copied from datasets.rb pattern)
      def http_request(method, path, params: {}, payload: nil, base_url: nil, parse_json: true)
        base = base_url || @state.api_url
        uri = URI("#{base}#{path}")
        uri.query = URI.encode_www_form(params) unless params.empty?

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

        request["Authorization"] = "Bearer #{@state.api_key}"

        start_time = Time.now
        Log.debug("[API] #{method.upcase} #{uri}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        response = http.request(request)

        duration_ms = ((Time.now - start_time) * 1000).round(2)
        Log.debug("[API] #{method.upcase} #{uri} -> #{response.code} (#{duration_ms}ms, #{response.body.bytesize} bytes)")

        unless response.is_a?(Net::HTTPSuccess)
          Log.debug("[API] Error response body: #{response.body}")
          raise Error, "HTTP #{response.code} for #{method.upcase} #{uri}: #{response.body}"
        end

        parse_json ? JSON.parse(response.body) : response
      end

      def http_post_json_raw(path, payload)
        http_request(:post, path, payload: payload, parse_json: false)
      end
    end
  end
end
