# frozen_string_literal: true

require "test_helper"
require "braintrust/span_cache"

module Braintrust
  class SpanCacheTest < Minitest::Test
    def setup
      @cache = SpanCache.new
    end

    def test_disabled_by_default
      refute @cache.enabled?
      assert_nil @cache.get("root1")
      assert_equal 0, @cache.size
    end

    def test_write_and_read_when_disabled
      @cache.write("root1", "span1", {input: "test"})
      assert_nil @cache.get("root1")
      assert_equal 0, @cache.size
    end

    def test_start_enables_and_clears
      @cache.start
      assert @cache.enabled?
      assert_equal 0, @cache.size
    end

    def test_write_and_read_when_enabled
      @cache.start
      @cache.write("root1", "span1", {input: "test", output: "result"})

      spans = @cache.get("root1")
      assert_equal 1, spans.size
      assert_equal "test", spans.first[:input]
      assert_equal "result", spans.first[:output]
    end

    def test_write_multiple_spans_same_root
      @cache.start
      @cache.write("root1", "span1", {input: "test1"})
      @cache.write("root1", "span2", {input: "test2"})

      spans = @cache.get("root1")
      assert_equal 2, spans.size
    end

    def test_merge_behavior
      @cache.start
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
      @cache.start
      @cache.write("root1", "span1", {input: "test", output: "result"})
      @cache.write("root1", "span1", {input: nil, metadata: {a: 1}})

      spans = @cache.get("root1")
      span = spans.first
      assert_equal "test", span[:input]
      assert_equal "result", span[:output]
      assert_equal({a: 1}, span[:metadata])
    end

    def test_has_returns_true_when_cached
      @cache.start
      @cache.write("root1", "span1", {input: "test"})
      assert @cache.has?("root1")
      refute @cache.has?("root2")
    end

    def test_has_returns_false_when_disabled
      @cache.start
      @cache.write("root1", "span1", {input: "test"})
      @cache.stop
      refute @cache.has?("root1")
    end

    def test_clear_single_entry
      @cache.start
      @cache.write("root1", "span1", {input: "test1"})
      @cache.write("root2", "span2", {input: "test2"})

      @cache.clear("root1")
      assert_nil @cache.get("root1")
      assert_equal 1, @cache.get("root2").size
    end

    def test_clear_all_entries
      @cache.start
      @cache.write("root1", "span1", {input: "test1"})
      @cache.write("root2", "span2", {input: "test2"})

      @cache.clear
      assert_equal 0, @cache.size
    end

    def test_stop_disables_and_clears
      @cache.start
      @cache.write("root1", "span1", {input: "test"})
      @cache.stop

      refute @cache.enabled?
      assert_equal 0, @cache.size
    end

    def test_disable_without_clearing
      @cache.start
      @cache.write("root1", "span1", {input: "test"})
      @cache.disable

      refute @cache.enabled?
      assert_equal 1, @cache.size
      assert_nil @cache.get("root1")
    end

    def test_size_returns_number_of_root_spans
      @cache.start
      @cache.write("root1", "span1", {input: "test1"})
      @cache.write("root1", "span2", {input: "test2"})
      @cache.write("root2", "span3", {input: "test3"})

      assert_equal 2, @cache.size
    end

    def test_ttl_expiration
      cache = SpanCache.new(ttl: 0.1)
      cache.start
      cache.write("root1", "span1", {input: "test"})

      assert cache.has?("root1")
      sleep 0.15

      assert_nil cache.get("root1")
      assert_equal 0, cache.size
    end

    def test_lru_eviction
      cache = SpanCache.new(max_entries: 2)
      cache.start

      cache.write("root1", "span1", {input: "test1"})
      sleep 0.001
      cache.write("root2", "span2", {input: "test2"})
      sleep 0.001
      cache.get("root1")
      sleep 0.001
      cache.write("root3", "span3", {input: "test3"})

      assert cache.has?("root1")
      refute cache.has?("root2")
      assert cache.has?("root3")
    end

    def test_thread_safety
      @cache.start
      threads = []

      10.times do |i|
        threads << Thread.new do
          100.times do |j|
            @cache.write("root#{i}", "span#{j}", {input: "test#{i}-#{j}"})
          end
        end
      end

      threads.each(&:join)

      assert_equal 10, @cache.size

      10.times do |i|
        spans = @cache.get("root#{i}")
        assert_equal 100, spans.size
      end
    end
  end
end
