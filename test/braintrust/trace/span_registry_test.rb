# frozen_string_literal: true

require "test_helper"
require "braintrust/trace/span_registry"
require "braintrust/span_cache"

module Braintrust
  module Trace
    class SpanRegistryTest < Minitest::Test
      def setup
        # Clean up any existing registration
        SpanRegistry.unregister
        @span_cache = SpanCache.new
      end

      def teardown
        # Clean up after each test
        SpanRegistry.unregister
      end

      def test_register_and_current
        SpanRegistry.register(@span_cache)

        assert_equal @span_cache, SpanRegistry.current
      end

      def test_current_returns_nil_when_not_registered
        assert_nil SpanRegistry.current
      end

      def test_unregister
        SpanRegistry.register(@span_cache)
        assert_equal @span_cache, SpanRegistry.current

        SpanRegistry.unregister
        assert_nil SpanRegistry.current
      end

      def test_registered_predicate
        refute SpanRegistry.registered?

        SpanRegistry.register(@span_cache)
        assert SpanRegistry.registered?

        SpanRegistry.unregister
        refute SpanRegistry.registered?
      end

      def test_thread_isolation
        # Register in main thread
        SpanRegistry.register(@span_cache)
        assert_equal @span_cache, SpanRegistry.current

        # Create new thread - should not see main thread's registration
        other_thread_result = nil
        thread = Thread.new do
          other_thread_result = SpanRegistry.current
        end
        thread.join

        assert_nil other_thread_result

        # Main thread should still have its registration
        assert_equal @span_cache, SpanRegistry.current
      end

      def test_multiple_threads_can_register_independently
        cache1 = SpanCache.new
        cache2 = SpanCache.new

        # Register cache1 in main thread
        SpanRegistry.register(cache1)

        # Register cache2 in another thread
        thread = Thread.new do
          SpanRegistry.register(cache2)
          assert_equal cache2, SpanRegistry.current
        end
        thread.join

        # Main thread should still have cache1
        assert_equal cache1, SpanRegistry.current
      end

      def test_overwriting_registration
        cache1 = SpanCache.new
        cache2 = SpanCache.new

        SpanRegistry.register(cache1)
        assert_equal cache1, SpanRegistry.current

        # Register cache2 in same thread - should overwrite
        SpanRegistry.register(cache2)
        assert_equal cache2, SpanRegistry.current
      end
    end
  end
end
