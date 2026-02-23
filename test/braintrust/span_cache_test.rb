# frozen_string_literal: true

require "test_helper"
require "braintrust/span_cache"

module Braintrust
  class SpanCacheTest < Minitest::Test
    def setup
      @cache = SpanCache.new
      # Clean up thread-local storage
      Thread.current[:braintrust_span_cache_data] = nil
    end

    def teardown
      Thread.current[:braintrust_span_cache_data] = nil
    end

    def test_write_and_read
      @cache.write("root1", "span1", {input: "test", output: "result"})

      spans = @cache.get("root1")
      assert_equal 1, spans.size
      assert_equal "test", spans.first[:input]
      assert_equal "result", spans.first[:output]
    end

    def test_write_multiple_spans_same_root
      @cache.write("root1", "span1", {input: "test1"})
      @cache.write("root1", "span2", {input: "test2"})

      spans = @cache.get("root1")
      assert_equal 2, spans.size
    end

    def test_merge_behavior
      @cache.write("root1", "span1", {input: "test", metadata: {a: 1}})
      @cache.write("root1", "span1", {output: "result", metadata: {b: 2}})

      spans = @cache.get("root1")
      assert_equal 1, spans.size
      span = spans.first
      assert_equal "test", span[:input]
      assert_equal "result", span[:output]
      assert_equal({b: 2}, span[:metadata])
    end

    def test_merge_with_nil_values
      @cache.write("root1", "span1", {input: "test", output: "result"})
      @cache.write("root1", "span1", {input: nil, metadata: {a: 1}})

      spans = @cache.get("root1")
      span = spans.first
      assert_equal "test", span[:input]
      assert_equal "result", span[:output]
      assert_equal({a: 1}, span[:metadata])
    end

    def test_has_returns_true_when_cached
      @cache.write("root1", "span1", {input: "test"})
      assert @cache.has?("root1")
      refute @cache.has?("root2")
    end

    def test_clear_all_clears_thread_local_storage
      @cache.write("root1", "span1", {input: "test"})

      assert @cache.get("root1")

      @cache.clear_all
      assert_nil @cache.get("root1")
      assert_equal 0, @cache.size
    end

    def test_size_returns_number_of_root_spans
      @cache.write("root1", "span1", {input: "test1"})
      @cache.write("root1", "span2", {input: "test2"})
      @cache.write("root2", "span3", {input: "test3"})

      assert_equal 2, @cache.size
    end

    def test_ttl_expiration
      cache = SpanCache.new(ttl: 0.1)
      cache.write("root1", "span1", {input: "test"})

      assert cache.has?("root1")
      sleep 0.15

      refute cache.has?("root1")
      assert_equal 0, cache.size
    end

    def test_lru_eviction
      cache = SpanCache.new(max_entries: 2)

      cache.write("root1", "span1", {input: "test1"})
      sleep 0.001
      cache.write("root2", "span2", {input: "test2"})
      sleep 0.001
      cache.get("root1") # Access root1 to make it more recent
      sleep 0.001
      cache.write("root3", "span3", {input: "test3"})

      assert cache.has?("root1")
      refute cache.has?("root2") # LRU victim
      assert cache.has?("root3")
    end

    def test_thread_isolation
      # Write in main thread
      @cache.write("root1", "span1", {input: "main"})

      # Check from another thread - should not see main thread's data
      other_result = nil
      thread = Thread.new do
        other_result = @cache.get("root1")
      end
      thread.join

      assert_nil other_result
      assert @cache.get("root1") # Main thread still has data
    end

    def test_writes_to_thread_local_storage_directly
      # SpanCache writes to thread-local storage directly
      @cache.write("root1", "span1", {input: "test"})

      # Data is written to thread-local storage
      spans = @cache.get("root1")
      assert_equal 1, spans.size
      assert_equal "test", spans.first[:input]
    end

    def test_multiple_caches_independent
      cache1 = SpanCache.new
      cache2 = SpanCache.new

      # Write to cache1 in main thread
      cache1.write("root1", "span1", {input: "cache1"})

      # Write to cache2 in another thread
      thread = Thread.new do
        cache2.write("root2", "span2", {input: "cache2"})

        # Verify cache2 has its data
        assert cache2.get("root2")
        # Verify cache2 doesn't have cache1's data
        assert_nil cache2.get("root1")
      end
      thread.join

      # Main thread should have cache1 data
      assert cache1.get("root1")
      # Main thread shouldn't have cache2 data (different thread)
      assert_nil cache1.get("root2")
    end
  end
end
