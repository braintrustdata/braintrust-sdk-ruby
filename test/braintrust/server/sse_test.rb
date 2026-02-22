# frozen_string_literal: true

require "test_helper"
require "braintrust/server"

class Braintrust::Server::SSEBodyTest < Minitest::Test
  def test_each_yields_formatted_sse_chunks
    body = Braintrust::Server::SSEBody.new do |sse|
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
    body = Braintrust::Server::SSEBody.new do |sse|
      call_count += 1
      sse.event("ping", "")
    end

    body.each { |_| }
    body.each { |_| }

    assert_equal 2, call_count
  end

  def test_body_concatenates_to_valid_sse_stream
    body = Braintrust::Server::SSEBody.new do |sse|
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
end

class Braintrust::Server::SSEWriterTest < Minitest::Test
  def test_event_formats_type_and_data
    chunks = []
    writer = Braintrust::Server::SSEWriter.new { |chunk| chunks << chunk }

    writer.event("progress", '{"key":"value"}')

    assert_equal 1, chunks.length
    assert_equal "event: progress\ndata: {\"key\":\"value\"}\n\n", chunks[0]
  end

  def test_event_with_empty_data
    chunks = []
    writer = Braintrust::Server::SSEWriter.new { |chunk| chunks << chunk }

    writer.event("done", "")

    assert_equal "event: done\ndata: \n\n", chunks[0]
  end

  def test_event_default_data_is_empty
    chunks = []
    writer = Braintrust::Server::SSEWriter.new { |chunk| chunks << chunk }

    writer.event("done")

    assert_equal "event: done\ndata: \n\n", chunks[0]
  end
end
