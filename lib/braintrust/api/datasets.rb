# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../logger"

module Braintrust
  class API
    # Datasets API namespace
    # Provides methods for creating, fetching, and querying datasets
    class Datasets
      def initialize(api)
        @api = api
        @state = api.state
      end

      # List datasets with optional filters
      # GET /v1/dataset?project_name=X&dataset_name=Y&...
      # @param project_name [String, nil] Filter by project name
      # @param dataset_name [String, nil] Filter by dataset name
      # @param project_id [String, nil] Filter by project ID
      # @param limit [Integer, nil] Limit number of results
      # @return [Hash] Response with "objects" array
      def list(project_name: nil, dataset_name: nil, project_id: nil, limit: nil)
        params = {}
        params["project_name"] = project_name if project_name
        params["dataset_name"] = dataset_name if dataset_name
        params["project_id"] = project_id if project_id
        params["limit"] = limit if limit

        http_get("/v1/dataset", params)
      end

      # Fetch exactly one dataset by project + name (convenience method)
      # @param project_name [String] Project name
      # @param name [String] Dataset name
      # @return [Hash] Dataset metadata
      # @raise [Braintrust::Error] if dataset not found
      def get(project_name:, name:)
        result = list(project_name: project_name, dataset_name: name)
        metadata = result["objects"]&.first
        raise Error, "Dataset '#{name}' not found in project '#{project_name}'" unless metadata
        metadata
      end

      # Fetch dataset metadata by ID
      # GET /v1/dataset/{id}
      # @param id [String] Dataset UUID
      # @return [Hash] Dataset metadata
      def get_by_id(id:)
        http_get("/v1/dataset/#{id}")
      end

      # Create or register a dataset (idempotent)
      # Uses app API /api/dataset/register which is idempotent - calling this method
      # multiple times with the same name will return the existing dataset.
      # @param project_name [String, nil] Project name
      # @param project_id [String, nil] Project ID
      # @param name [String] Dataset name
      # @param description [String, nil] Optional description
      # @param metadata [Hash, nil] Optional metadata
      # @return [Hash] Response with "project", "dataset", and optional "found_existing" keys.
      #   The "found_existing" field is true if the dataset already existed, false/nil if newly created.
      def create(name:, project_name: nil, project_id: nil, description: nil, metadata: nil)
        payload = {dataset_name: name, org_id: @state.org_id}
        payload[:project_name] = project_name if project_name
        payload[:project_id] = project_id if project_id
        payload[:description] = description if description
        payload[:metadata] = metadata if metadata

        http_post_json_app("/api/dataset/register", payload)
      end

      # Insert events into a dataset
      # POST /v1/dataset/{id}/insert
      # @param id [String] Dataset UUID
      # @param events [Array<Hash>] Array of event records
      # @return [Hash] Insert response
      def insert(id:, events:)
        http_post_json("/v1/dataset/#{id}/insert", {events: events})
      end

      # Generate a permalink URL to view a dataset in the Braintrust UI
      # @param id [String] Dataset UUID
      # @return [String] Permalink URL
      def permalink(id:)
        "#{@state.app_url}/app/#{@state.org_name}/object?object_type=dataset&object_id=#{id}"
      end

      # Fetch dataset rows directly (simpler than BTQL)
      # GET /v1/dataset/{id}/fetch
      #
      # This is the preferred method for fetching dataset rows for evaluation.
      # It returns rows in a format ready for use with EvalCase.from_hash.
      #
      # @param id [String] Dataset UUID
      # @param limit [Integer] Max rows to fetch (default: 1000)
      # @return [Array<Hash>] Array of dataset rows with input, expected, metadata, etc.
      #
      # @example Fetch rows for evaluation
      #   rows = api.datasets.fetch_rows(id: dataset_id)
      #   cases = rows.map { |row| Braintrust::Remote::EvalCase.from_hash(row) }
      #
      def fetch_rows(id:, limit: 1000)
        result = http_get("/v1/dataset/#{id}/fetch", {"limit" => limit})
        result["events"] || []
      end

      # Fetch records from dataset using BTQL
      # POST /btql
      # @param id [String] Dataset UUID
      # @param limit [Integer] Max records per page (default: 1000)
      # @param cursor [String, nil] Pagination cursor
      # @param version [String, nil] Dataset version
      # @return [Hash] Hash with :records array and :cursor string
      def fetch(id:, limit: 1000, cursor: nil, version: nil)
        query = {
          from: {
            op: "function",
            name: {op: "ident", name: ["dataset"]},
            args: [{op: "literal", value: id}]
          },
          select: [{op: "star"}],
          limit: limit
        }
        query[:cursor] = cursor if cursor

        payload = {query: query, fmt: "jsonl"}
        payload[:version] = version if version

        response = http_post_json_raw("/btql", payload)

        # Parse JSONL response
        records = response.body.lines
          .map { |line| JSON.parse(line.strip) if line.strip.length > 0 }
          .compact

        # Extract pagination cursor from headers
        next_cursor = response["x-bt-cursor"] || response["x-amz-meta-bt-cursor"]

        {records: records, cursor: next_cursor}
      end

      private

      # Core HTTP request method with logging
      # @param method [Symbol] :get or :post
      # @param path [String] API path
      # @param params [Hash] Query params (for GET)
      # @param payload [Hash, nil] JSON payload (for POST)
      # @param base_url [String, nil] Override base URL (default: api_url)
      # @param parse_json [Boolean] Whether to parse response as JSON (default: true)
      # @return [Hash, Net::HTTPResponse] Parsed JSON or raw response
      def http_request(method, path, params: {}, payload: nil, base_url: nil, parse_json: true)
        # Build URI
        base = base_url || @state.api_url
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

        parse_json ? JSON.parse(response.body) : response
      end

      # HTTP GET with query params - returns parsed JSON
      def http_get(path, params = {})
        http_request(:get, path, params: params)
      end

      # HTTP POST with JSON body - returns parsed JSON
      def http_post_json(path, payload)
        http_request(:post, path, payload: payload)
      end

      # HTTP POST to app URL (not API URL) - returns parsed JSON
      def http_post_json_app(path, payload)
        http_request(:post, path, payload: payload, base_url: @state.app_url)
      end

      # HTTP POST with JSON body - returns raw response (for header access)
      def http_post_json_raw(path, payload)
        http_request(:post, path, payload: payload, parse_json: false)
      end
    end
  end
end
