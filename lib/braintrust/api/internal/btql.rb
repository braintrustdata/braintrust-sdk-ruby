# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../../internal/http"

module Braintrust
  class API
    module Internal
      # Internal BTQL client for querying spans.
      # Not part of the public API — instantiated directly where needed.
      class BTQL
        def initialize(state)
          @state = state
        end

        # Query spans belonging to a specific trace within an object.
        #
        # Builds a BTQL SQL query that matches the root_span_id and excludes scorer spans.
        # Returns a single-shot result; callers are responsible for retry and error handling.
        #
        # @param object_type [String] e.g. "experiment"
        # @param object_id [String] Object UUID
        # @param root_span_id [String] Hex trace ID of the root span
        # @return [Array(Array<Hash>, String)] [rows, freshness]
        def trace_spans(object_type:, object_id:, root_span_id:)
          query = build_trace_query(
            object_type: object_type,
            object_id: object_id,
            root_span_id: root_span_id
          )
          execute_query(query: query, fmt: "jsonl")
        end

        private

        # Build a BTQL SQL query string for fetching trace spans.
        #
        # Selects all spans for a given root_span_id, excluding scorer spans
        # (span_attributes.type = 'score').
        #
        # @param object_type [String] e.g. "experiment"
        # @param object_id [String] Object UUID
        # @param root_span_id [String] Hex trace ID
        # @return [String] BTQL SQL query
        def build_trace_query(object_type:, object_id:, root_span_id:)
          escaped_root = root_span_id.gsub("'", "''")
          escaped_id = object_id.gsub("'", "''")

          "SELECT * FROM #{object_type}('#{escaped_id}') " \
            "WHERE root_span_id = '#{escaped_root}' " \
            "AND span_attributes.type != 'score' " \
            "LIMIT 1000"
        end

        # Execute a BTQL query and parse the JSONL response.
        #
        # @param payload [Hash] BTQL request payload
        # @return [Array(Array<Hash>, String)] [parsed_rows, freshness_state]
        def execute_query(payload)
          uri = URI("#{@state.api_url}/btql")

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request["Authorization"] = "Bearer #{@state.api_key}"
          request["Accept"] = "application/x-jsonlines"
          request.body = JSON.dump(payload)

          response = Braintrust::Internal::Http.with_redirects(uri, request)

          unless response.is_a?(Net::HTTPSuccess)
            raise Braintrust::Error, "HTTP #{response.code} for POST #{uri}: #{response.body}"
          end

          freshness = response["x-bt-freshness-state"] || "complete"
          [parse_jsonl(response.body), freshness]
        end

        # Parse a JSONL response body into an array of hashes.
        #
        # @param body [String] JSONL response body
        # @return [Array<Hash>]
        def parse_jsonl(body)
          body.each_line.filter_map do |line|
            line = line.strip
            next if line.empty?
            JSON.parse(line)
          end
        end
      end
    end
  end
end
