# frozen_string_literal: true

require "test_helper"

module Braintrust
  module Server
    class SSEBodyTest < Minitest::Test
      def setup
        skip_unless_server!
      end

      def test_each_yields_formatted_sse_chunks
        body = SSEBody.new do |sse|
          sse.event("progress", '{"data":"hello"}')
          sse.event("done", "")
        end

        chunks = []
        body.each { |chunk| chunks << chunk }

        assert_equal 2, chunks.length
        assert_equal "event: progress\ndata: {\"data\":\"hello\"}\n\n", chunks[0]
        assert_equal "event: done\ndata: \n\n", chunks[1]
      end

      def test_each_can_be_called_multiple_times
        call_count = 0
        body = SSEBody.new do |sse|
          call_count += 1
          sse.event("ping", "")
        end

        body.each { |_| }
        body.each { |_| }

        assert_equal 2, call_count
      end

      def test_body_concatenates_to_valid_sse_stream
        body = SSEBody.new do |sse|
          sse.event("a", "1")
          sse.event("b", "2")
          sse.event("c", "3")
        end

        full = +""
        body.each { |chunk| full << chunk }

        events = full.split("\n\n").reject(&:empty?)
        assert_equal 3, events.length
        assert_equal "event: a\ndata: 1", events[0]
        assert_equal "event: b\ndata: 2", events[1]
        assert_equal "event: c\ndata: 3", events[2]
      end

      def test_does_not_respond_to_call
        body = SSEBody.new { |_| }
        refute body.respond_to?(:call), "SSEBody should not respond to call"
      end
    end

    class SSEStreamBodyTest < Minitest::Test
      def setup
        skip_unless_server!
      end

      def test_call_writes_to_stream_and_closes
        body = SSEStreamBody.new do |sse|
          sse.event("progress", '{"data":"hello"}')
          sse.event("done", "")
        end

        written = []
        closed = false
        stream = Object.new
        stream.define_singleton_method(:write) { |data| written << data }
        stream.define_singleton_method(:close) { closed = true }

        body.call(stream)

        assert_equal 2, written.length
        assert_equal "event: progress\ndata: {\"data\":\"hello\"}\n\n", written[0]
        assert_equal "event: done\ndata: \n\n", written[1]
        assert closed, "Stream should be closed after call"
      end

      def test_call_closes_stream_on_error
        body = SSEStreamBody.new do |sse|
          sse.event("progress", "ok")
          raise "boom"
        end

        closed = false
        stream = Object.new
        stream.define_singleton_method(:write) { |_| }
        stream.define_singleton_method(:close) { closed = true }

        assert_raises(RuntimeError) { body.call(stream) }
        assert closed, "Stream should be closed even when block raises"
      end

      def test_does_not_respond_to_each
        body = SSEStreamBody.new { |_| }
        refute body.respond_to?(:each), "SSEStreamBody should not respond to each"
      end
    end

    class SSEWriterTest < Minitest::Test
      def setup
        skip_unless_server!
      end

      def test_event_formats_type_and_data
        chunks = []
        writer = SSEWriter.new { |chunk| chunks << chunk }

        writer.event("progress", '{"key":"value"}')

        assert_equal 1, chunks.length
        assert_equal "event: progress\ndata: {\"key\":\"value\"}\n\n", chunks[0]
      end

      def test_event_with_empty_data
        chunks = []
        writer = SSEWriter.new { |chunk| chunks << chunk }

        writer.event("done", "")

        assert_equal "event: done\ndata: \n\n", chunks[0]
      end

      def test_event_default_data_is_empty
        chunks = []
        writer = SSEWriter.new { |chunk| chunks << chunk }

        writer.event("done")

        assert_equal "event: done\ndata: \n\n", chunks[0]
      end
    end
  end
end
