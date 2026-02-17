# frozen_string_literal: true

module Braintrust
  module Trace
    # Thread-safe singleton registry that maps the current evaluation context
    # to its SpanCache. Allows SpanProcessor to find the active eval's cache
    # without relying on global state.
    #
    # The registry uses thread-local storage to associate each thread with
    # its current SpanCache, enabling lock-free lookups.
    class SpanRegistry
      # Thread-local key for storing the current span cache
      THREAD_KEY = :braintrust_span_registry_cache

      class << self
        # Register a span cache for the current thread
        # @param span_cache [SpanCache] The span cache to register
        def register(span_cache)
          Thread.current[THREAD_KEY] = span_cache
        end

        # Get the currently registered span cache for this thread
        # @return [SpanCache, nil] The registered span cache, or nil if none
        def current
          Thread.current[THREAD_KEY]
        end

        # Unregister the current thread's span cache
        def unregister
          Thread.current[THREAD_KEY] = nil
        end

        # Check if a span cache is registered for the current thread
        # @return [Boolean]
        def registered?
          !Thread.current[THREAD_KEY].nil?
        end
      end
    end
  end
end
