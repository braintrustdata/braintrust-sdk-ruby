# frozen_string_literal: true

module Braintrust
  # Thread-safe in-memory cache for spans during evaluation runs.
  # Stores spans indexed by root_span_id to enable fast local lookups
  # before falling back to BTQL queries.
  class SpanCache
    DEFAULT_TTL = 300 # 5 minutes
    DEFAULT_MAX_ENTRIES = 1000

    def initialize(ttl: DEFAULT_TTL, max_entries: DEFAULT_MAX_ENTRIES)
      @ttl = ttl
      @max_entries = max_entries
      @cache = {} # {root_span_id => {spans: {span_id => data}, accessed_at: Time}}
      @mutex = Mutex.new
      @enabled = false
    end

    # Write or merge a span into the cache
    # @param root_span_id [String] The root span ID
    # @param span_id [String] The span ID
    # @param span_data [Hash] Span data (input, output, metadata, etc.)
    def write(root_span_id, span_id, span_data)
      return unless @enabled

      @mutex.synchronize do
        evict_expired
        evict_lru if @cache.size >= @max_entries

        @cache[root_span_id] ||= {spans: {}, accessed_at: Time.now}
        entry = @cache[root_span_id]

        # Merge: incoming non-nil values override existing
        existing = entry[:spans][span_id] || {}
        entry[:spans][span_id] = existing.merge(span_data.compact)
        entry[:accessed_at] = Time.now
      end
    end

    # Get all cached spans for a root span
    # @param root_span_id [String] The root span ID
    # @return [Array<Hash>, nil] Array of span data hashes, or nil if not cached
    def get(root_span_id)
      return nil unless @enabled

      @mutex.synchronize do
        evict_expired
        entry = @cache[root_span_id]
        return nil unless entry

        entry[:accessed_at] = Time.now
        entry[:spans].values
      end
    end

    # Check if root span has cached data
    # @param root_span_id [String] The root span ID
    # @return [Boolean]
    def has?(root_span_id)
      return false unless @enabled

      @mutex.synchronize do
        evict_expired
        @cache.key?(root_span_id)
      end
    end

    # Clear one or all cache entries
    # @param root_span_id [String, nil] Specific root span ID, or nil to clear all
    def clear(root_span_id = nil)
      @mutex.synchronize do
        if root_span_id
          @cache.delete(root_span_id)
        else
          @cache.clear
        end
      end
    end

    # Number of cached root spans
    # @return [Integer]
    def size
      @mutex.synchronize { @cache.size }
    end

    # Check if cache is enabled
    # @return [Boolean]
    def enabled?
      @enabled
    end

    # Enable and clear the cache (called at eval start)
    def start
      @mutex.synchronize do
        @enabled = true
        @cache.clear
      end
    end

    # Disable and clear the cache (called at eval end)
    def stop
      @mutex.synchronize do
        @enabled = false
        @cache.clear
      end
    end

    # Disable the cache without clearing
    def disable
      @enabled = false
    end

    private

    def evict_expired
      now = Time.now
      @cache.delete_if { |_id, entry| now - entry[:accessed_at] > @ttl }
    end

    def evict_lru
      return if @cache.size < @max_entries

      # Remove the least recently accessed entry
      lru_key = @cache.min_by { |_id, entry| entry[:accessed_at] }&.first
      @cache.delete(lru_key) if lru_key
    end
  end
end
