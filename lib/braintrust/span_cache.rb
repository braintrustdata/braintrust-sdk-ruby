# frozen_string_literal: true

module Braintrust
  # Lock-free in-memory cache for spans during evaluation runs.
  # Uses thread-local storage for zero-contention performance in multi-threaded evals.
  # Each thread maintains its own cache, eliminating all synchronization overhead.
  #
  # Lifecycle is managed by EvalContext - no start/stop/enabled state needed.
  class SpanCache
    DEFAULT_TTL = 300 # 5 minutes
    DEFAULT_MAX_ENTRIES = 1000
    THREAD_KEY = :braintrust_span_cache_data

    def initialize(ttl: DEFAULT_TTL, max_entries: DEFAULT_MAX_ENTRIES)
      @ttl = ttl
      @max_entries = max_entries
    end

    # Write or merge a span into the cache (thread-local, lock-free)
    # @param root_span_id [String] The root span ID
    # @param span_id [String] The span ID
    # @param span_data [Hash] Span data (input, output, metadata, etc.)
    def write(root_span_id, span_id, span_data)
      local = Thread.current[THREAD_KEY] ||= {}

      evict_expired(local)
      evict_lru(local) if local.size >= @max_entries

      local[root_span_id] ||= {spans: {}, accessed_at: Time.now}
      entry = local[root_span_id]

      # Merge: incoming non-nil values override existing
      existing = entry[:spans][span_id] || {}
      entry[:spans][span_id] = existing.merge(span_data.compact)
      entry[:accessed_at] = Time.now
    end

    # Get all cached spans for a root span (thread-local, lock-free)
    # @param root_span_id [String] The root span ID
    # @return [Array<Hash>, nil] Array of span data hashes, or nil if not cached
    def get(root_span_id)
      local = Thread.current[THREAD_KEY] || {}
      entry = local[root_span_id]
      return nil unless entry

      entry[:accessed_at] = Time.now
      entry[:spans].values
    end

    # Check if root span has cached data
    # @param root_span_id [String] The root span ID
    # @return [Boolean]
    def has?(root_span_id)
      local = Thread.current[THREAD_KEY] || {}
      evict_expired(local)
      local.key?(root_span_id)
    end

    # Clear all cached data for the current thread
    # Used by EvalContext.dispose for cleanup
    def clear_all
      Thread.current[THREAD_KEY] = nil
    end

    # Number of cached root spans in current thread
    # @return [Integer]
    def size
      local = Thread.current[THREAD_KEY] || {}
      local.size
    end

    # Evict expired entries from cache
    def evict_expired(cache)
      now = Time.now
      cache.delete_if { |_id, entry| now - entry[:accessed_at] > @ttl }
    end

    # Evict least recently used entry
    def evict_lru(cache)
      return if cache.size < @max_entries

      # Remove the least recently accessed entry
      lru_key = cache.min_by { |_id, entry| entry[:accessed_at] }&.first
      cache.delete(lru_key) if lru_key
    end
  end
end
