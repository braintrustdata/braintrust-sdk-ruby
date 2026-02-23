# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "api"
require_relative "span_cache"

module Braintrust
  # TraceContext provides scorers access to span data from the evaluation trace.
  # It queries BTQL and caches the results internally for subsequent access.
  # The cache is only populated by BTQL API results, never by the tracer.
  class TraceContext
    MAX_RETRIES = 8
    INITIAL_BACKOFF = 0.25 # seconds

    def initialize(object_type:, object_id:, root_span_id:, state:, ensure_spans_flushed: nil)
      @object_type = object_type
      @object_id = object_id
      @root_span_id = root_span_id
      @state = state
      @ensure_spans_flushed = ensure_spans_flushed
      @spans_ready_mutex = Mutex.new
      @spans_ready = false
      # Internal cache populated only from BTQL responses
      @btql_cache = SpanCache.new
    end

    # Returns configuration hash
    # @return [Hash] Configuration with object_type, object_id, root_span_id
    def configuration
      {
        object_type: @object_type,
        object_id: @object_id,
        root_span_id: @root_span_id
      }
    end

    # Get spans for this trace, optionally filtered by span type.
    # Filters out scorer spans (purpose == "scorer").
    # @param span_type [Array<String>, String, nil] Types to filter by (e.g., "llm", "score")
    # @return [Array<Hash>] Array of span hashes with keys: input, output, metadata, span_id, span_parents, span_attributes
    def get_spans(span_type: nil)
      # Normalize span_type to array
      types = span_type && Array(span_type)

      # Try cache first, otherwise fetch via BTQL and populate cache
      cached = @btql_cache.get(@root_span_id)
      spans = cached || fetch_and_cache_spans(types)

      # Filter out scorer spans
      spans = spans.reject { |s| s.dig(:span_attributes, :purpose) == "scorer" }

      # Filter by type if specified
      if types
        spans = spans.select { |s| types.include?(s.dig(:span_attributes, :type)) }
      end

      spans
    end

    # Reconstruct message thread from LLM spans.
    # Deduplicates input messages by content hash, always includes output messages.
    # @return [Array<Hash>] Array of message hashes
    def get_thread
      llm_spans = get_spans(span_type: "llm")

      messages = []
      seen_inputs = Set.new

      llm_spans.each do |span|
        # Add input messages (deduplicated)
        input = span[:input]
        if input.is_a?(Hash) && input[:messages].is_a?(Array)
          input[:messages].each do |msg|
            msg_hash = msg.hash
            unless seen_inputs.include?(msg_hash)
              messages << msg
              seen_inputs.add(msg_hash)
            end
          end
        end

        # Always add output messages
        output = span[:output]
        if output.is_a?(Hash) && output[:choices].is_a?(Array)
          output[:choices].each do |choice|
            messages << choice[:message] if choice[:message]
          end
        end
      end

      messages
    end

    private

    # Ensure spans are flushed before querying (idempotent, thread-safe)
    def ensure_spans_ready
      @spans_ready_mutex.synchronize do
        return if @spans_ready

        @ensure_spans_flushed&.call
        @spans_ready = true
      end
    end

    # Fetch spans via BTQL with retry logic and populate the internal cache
    # @param types [Array<String>, nil] Span types to filter by (note: filtering happens after cache)
    # @return [Array<Hash>] Array of spans
    def fetch_and_cache_spans(types)
      ensure_spans_ready

      # Build AST filter (without type filtering, as we cache all spans)
      filter = build_btql_filter(nil)

      retries = 0
      backoff = INITIAL_BACKOFF

      loop do
        result = query_btql(filter)

        # Check freshness
        if result[:freshness_state] == "complete" || retries >= MAX_RETRIES
          # Populate cache with all spans for this root_span_id
          spans = result[:spans]
          spans.each do |span|
            @btql_cache.write(@root_span_id, span[:span_id], span)
          end
          return spans
        end

        # Exponential backoff
        sleep backoff
        backoff *= 2
        retries += 1
      end
    end

    # Build BTQL AST filter
    # @param types [Array<String>, nil] Span types to filter by
    # @return [Hash] AST filter object
    def build_btql_filter(types)
      # root_span_id = X
      root_filter = {
        path: ["root_span_id"],
        op: "=",
        value: @root_span_id
      }

      # (purpose IS NULL OR purpose != 'scorer')
      purpose_filter = {
        op: "or",
        operands: [
          {path: ["span_attributes", "purpose"], op: "is null"},
          {path: ["span_attributes", "purpose"], op: "!=", value: "scorer"}
        ]
      }

      # Combine with AND
      combined = {
        op: "and",
        operands: [root_filter, purpose_filter]
      }

      # Add type filter if specified
      if types && !types.empty?
        type_filter = {
          path: ["span_attributes", "type"],
          op: "in",
          value: types
        }
        combined[:operands] << type_filter
      end

      combined
    end

    # Query BTQL endpoint
    # @param filter [Hash] AST filter
    # @return [Hash] {spans: Array<Hash>, freshness_state: String}
    def query_btql(filter)
      api = API.new(state: @state)
      response = api.btql.query(
        query: filter,
        object_type: @object_type,
        object_id: @object_id,
        fmt: "jsonl"
      )

      # Parse JSONL response
      spans = response[:body].lines.map { |line| JSON.parse(line, symbolize_names: true) }

      {
        spans: spans.map { |s| normalize_span(s) },
        freshness_state: response[:freshness_state] || "complete"
      }
    rescue => e
      # On error, return empty result
      warn "BTQL query failed: #{e.message}"
      {spans: [], freshness_state: "complete"}
    end

    # Normalize span data from BTQL to match cache format
    # @param span [Hash] Raw span data from BTQL
    # @return [Hash] Normalized span
    def normalize_span(span)
      {
        input: span[:input],
        output: span[:output],
        metadata: span[:metadata],
        span_id: span[:span_id],
        span_parents: span[:span_parents],
        span_attributes: span[:span_attributes]
      }
    end
  end
end
