# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Braintrust
  module BTX
    # Fetches brainstore spans from the Braintrust backend via the BTQL HTTP API
    # (live mode). Retries with a fixed interval until all expected spans are
    # available (their output/metrics fields indexed).
    class SpanFetcher
      RETRY_INTERVAL = 30 # seconds
      MAX_WAIT = 600 # seconds

      def initialize(api_url:, api_key:)
        @api_url = api_url
        @api_key = api_key
      end

      # Resolve a project id from its name via the BTQL/projects API.
      def self.project_id_for(name, api_url:, api_key:)
        uri = URI("#{api_url}/v1/project?project_name=#{URI.encode_www_form_component(name)}")
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{api_key}"
        res = http_request(uri, req)
        raise "Failed to resolve project #{name.inspect}: HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
        body = JSON.parse(res.body)
        objects = body["objects"] || body
        proj = objects.is_a?(Array) ? objects.first : objects
        proj && (proj["id"] || proj.dig("project", "id"))
      end

      def self.http_request(uri, req)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.request(req)
      end

      # Fetch +num_expected+ child spans for +root_span_id+, retrying until ready.
      #
      # @return [Array<Hash>] brainstore spans (excluding root + scorer spans)
      def fetch(root_span_id, project_id, num_expected)
        total_wait = 0
        loop do
          spans = try_fetch(root_span_id, project_id)
          ready = spans.select { |s| span_ready?(s) }
          return spans if ready.length >= num_expected && spans.length >= num_expected

          if total_wait >= MAX_WAIT
            raise "BTX span fetch timed out after #{MAX_WAIT}s for root_span_id=#{root_span_id} " \
              "(got #{spans.length} spans, #{ready.length} ready, expected #{num_expected})"
          end
          sleep(RETRY_INTERVAL)
          total_wait += RETRY_INTERVAL
        end
      end

      private

      def try_fetch(root_span_id, project_id)
        payload = build_query(root_span_id, project_id)
        uri = URI("#{@api_url}/btql")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["Authorization"] = "Bearer #{@api_key}"
        req.body = JSON.dump(payload)

        res = self.class.http_request(uri, req)
        raise "BTQL HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

        rows = JSON.parse(res.body)["data"] || []
        # Filter scorer spans injected by the backend.
        rows.reject { |s| (s["span_attributes"] || {})["purpose"] == "scorer" }
      end

      def span_ready?(span)
        !span["output"].nil? || !span["metrics"].nil?
      end

      def build_query(root_span_id, project_id)
        {
          query: {
            select: [{op: "star"}],
            from: {
              op: "function",
              name: {op: "ident", name: ["project_logs"]},
              args: [{op: "literal", value: project_id}]
            },
            filter: {
              op: "and",
              left: {
                op: "eq",
                left: {op: "ident", name: ["root_span_id"]},
                right: {op: "literal", value: root_span_id}
              },
              right: {
                op: "ne",
                left: {op: "ident", name: ["span_parents"]},
                right: {op: "literal", value: nil}
              }
            },
            sort: [{expr: {op: "ident", name: ["created"]}, dir: "asc"}],
            limit: 1000
          },
          use_columnstore: true,
          use_brainstore: true,
          brainstore_realtime: true
        }
      end
    end
  end
end
