# frozen_string_literal: true

require_relative "../span_cache"

module Braintrust
  module Eval
    # Scoped context for a single evaluation run.
    # Owns lifecycle of span cache and other eval-specific resources.
    # Created at eval start, disposed at eval end.
    class Context
      attr_reader :experiment_id, :span_cache

      # @param experiment_id [String] The experiment ID
      # @param ttl [Integer] Span cache TTL in seconds (default: SpanCache::DEFAULT_TTL)
      # @param max_entries [Integer] Max cache entries (default: SpanCache::DEFAULT_MAX_ENTRIES)
      def initialize(experiment_id:, ttl: SpanCache::DEFAULT_TTL, max_entries: SpanCache::DEFAULT_MAX_ENTRIES)
        @experiment_id = experiment_id
        @span_cache = SpanCache.new(ttl: ttl, max_entries: max_entries)
      end

      # Dispose of resources (for eager cleanup)
      # Clears the span cache to free memory
      def dispose
        @span_cache.clear_all
      end
    end
  end
end
