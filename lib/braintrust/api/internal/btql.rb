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
        # Maximum number of retries before returning partial results.
        # Covers both freshness lag (partially indexed) and ingestion lag
        # (spans not yet visible to BTQL after OTel flush).
        MAX_FRESHNESS_RETRIES = 7

        # Base delay (seconds) between retries (doubles each attempt, capped).
        FRESHNESS_BASE_DELAY = 1.0

        # Maximum delay (seconds) between retries. Caps exponential growth
        # so we keep polling at a reasonable rate in the later window.
        # Schedule: 1, 2, 4, 8, 8, 8, 8 = ~39s total worst-case.
        MAX_FRESHNESS_DELAY = 8.0

        def initialize(state)
          @state = state
        end

        # Query spans belonging to a specific trace within an object.
        #
        # Builds a BTQL SQL query that matches the root_span_id and excludes scorer spans.
        # Retries with exponential backoff if the response indicates data is not yet fresh.
        #
        # @param object_type [String] e.g. "experiment"
        # @param object_id [String] Object UUID
        # @param root_span_id [String] Hex trace ID of the root span
        # @return [Array<Hash>] Parsed span data
        def trace_spans(object_type:, object_id:, root_span_id:)
          query = build_trace_query(
            object_type: object_type,
            object_id: object_id,
            root_span_id: root_span_id
          )
          payload = {query: query, fmt: "jsonl"}

          retries = 0
          loop do
            rows, freshness = execute_query(payload)
            # Return when data is fresh AND non-empty, or we've exhausted retries.
            # We retry on empty even when "complete" because there is ingestion lag
            # between OTel flush and BTQL indexing — the server may report "complete"
            # before it knows about newly-flushed spans.
            return rows if (freshness == "complete" && !rows.empty?) || retries >= MAX_FRESHNESS_RETRIES

            retries += 1
            delay = [FRESHNESS_BASE_DELAY * (2**(retries - 1)), MAX_FRESHNESS_DELAY].min
            sleep(delay)
          end
        rescue => e
          Braintrust::Log.debug("[BTQL] Query failed: #{e.message}")
          []
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
