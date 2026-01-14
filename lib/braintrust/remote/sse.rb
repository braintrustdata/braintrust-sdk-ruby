# frozen_string_literal: true

require "json"

module Braintrust
  module Remote
    # Server-Sent Events helpers for remote evaluations
    #
    # This module provides:
    # - SSE event serialization
    # - Standard SSE headers
    # - Streaming body classes for Rack responses
    #
    # These helpers work with any Rack-compatible server and don't require
    # the rack gem as a dependency.
    #
    # @example Serialize events
    #   SSE.serialize_event("progress", { output: "hello", scores: { accuracy: 1.0 } })
    #   # => "event: progress\ndata: {\"output\":\"hello\",\"scores\":{\"accuracy\":1.0}}\n\n"
    #
    # @example Use streaming body in Rack response
    #   events = []
    #   events << SSE.serialize_event("progress", data)
    #   events << SSE.serialize_event("done", nil)
    #   [200, SSE::HEADERS, SSE::BufferedBody.new(events)]
    #
    # @example Use queue-based streaming for true real-time
    #   queue = Queue.new
    #   Thread.new { run_eval { |event| queue.push(SSE.serialize_event("progress", event)) } }
    #   [200, SSE::HEADERS, SSE::QueueBody.new(queue)]
    #
    module SSE
      # Standard SSE response headers
      HEADERS = {
        "Content-Type" => "text/event-stream; charset=utf-8",
        "Cache-Control" => "no-cache",
        "Connection" => "keep-alive",
        "X-Accel-Buffering" => "no"
      }.freeze

      # Serialize data into SSE format
      #
      # @param event_type [String] The event type (e.g., "progress", "summary", "done")
      # @param data [Object, nil] The data to serialize (will be JSON encoded if not a String)
      # @return [String] SSE-formatted event string
      #
      # @example With hash data
      #   SSE.serialize_event("progress", { output: "hello" })
      #   # => "event: progress\ndata: {\"output\":\"hello\"}\n\n"
      #
      # @example With nil data (for "done" events)
      #   SSE.serialize_event("done", nil)
      #   # => "event: done\ndata: \n\n"
      #
      def self.serialize_event(event_type, data)
        data_str = case data
        when nil, ""
          ""
        when String
          data
        else
          data.to_json
        end

        "event: #{event_type}\ndata: #{data_str}\n\n"
      end

      # Get SSE headers with CORS headers for a given origin
      #
      # @param origin [String, nil] The request origin
      # @return [Hash] Headers hash
      #
      def self.headers_with_cors(origin)
        cors = ServerHelpers::CORS.headers_for_origin(origin)
        HEADERS.merge(cors)
      end

      # Build raw HTTP response headers for socket streaming (Rack hijack)
      #
      # This is used when writing directly to a socket, bypassing Rack's
      # response handling for true real-time streaming.
      #
      # @param origin [String, nil] The request origin for CORS headers
      # @param status [Integer] HTTP status code (default: 200)
      # @return [String] Complete HTTP response headers ready to write to socket
      #
      # @example With Rack hijack
      #   env["rack.hijack"].call
      #   io = env["rack.hijack_io"]
      #   io.write(SSE.http_response_headers(origin))
      #   io.flush
      #   # Now write SSE events...
      #
      def self.http_response_headers(origin, status: 200)
        cors = ServerHelpers::CORS.headers_for_origin(origin)

        lines = [
          "HTTP/1.1 #{status} OK",
          "Content-Type: text/event-stream; charset=utf-8",
          "Cache-Control: no-cache",
          "Connection: keep-alive"
        ]

        cors.each { |k, v| lines << "#{k}: #{v}" }

        # End headers with blank line
        lines << ""
        lines << ""

        lines.join("\r\n")
      end

      # Thread-safe event stream that writes to a queue
      #
      # Use this for true real-time streaming where events are sent
      # as they're generated, not buffered.
      #
      # @example
      #   queue = Queue.new
      #   stream = SSE::QueueStream.new(queue)
      #
      #   Thread.new do
      #     evaluator.run do |result|
      #       stream.event("progress", result)
      #     end
      #     stream.close
      #   end
      #
      #   [200, headers, SSE::QueueBody.new(queue)]
      #
      class QueueStream
        def initialize(queue)
          @queue = queue
          @closed = false
        end

        # Send an event to the stream
        #
        # @param event_type [String] Event type
        # @param data [Object] Event data
        #
        def event(event_type, data)
          return if @closed

          sse_event = SSE.serialize_event(event_type, data)
          Braintrust::Log.debug("[SSE-QUEUE] Enqueueing event: #{event_type}")
          @queue.push(sse_event)
        end

        # Close the stream
        # Signals to the body that no more events will be sent
        #
        def close
          return if @closed
          @closed = true
          @queue.push(:done)
          Braintrust::Log.debug("[SSE-QUEUE] Stream closed")
        end

        def closed?
          @closed
        end
      end

      # Rack body that reads from a queue
      #
      # Yields events as they become available, providing true streaming.
      # Implements the Rack body interface (#each, #close).
      #
      class QueueBody
        def initialize(queue)
          @queue = queue
        end

        def each
          Braintrust::Log.debug("[SSE-BODY] Starting to yield events")
          loop do
            event = @queue.pop # Blocks until event available
            break if event == :done

            Braintrust::Log.debug("[SSE-BODY] Yielding event")
            yield event
          end
          Braintrust::Log.debug("[SSE-BODY] All events yielded")
        end

        def close
          Braintrust::Log.debug("[SSE-BODY] Body closed")
        end
      end

      # Simple event stream that collects events in an array
      #
      # Use this when you need to collect all events before returning
      # the response (e.g., when true streaming isn't available).
      #
      # @example
      #   events = []
      #   stream = SSE::BufferedStream.new(events)
      #
      #   evaluator.run do |result|
      #     stream.event("progress", result)
      #   end
      #   stream.event("done", nil)
      #
      #   [200, headers, SSE::BufferedBody.new(events)]
      #
      class BufferedStream
        def initialize(events)
          @events = events
          @closed = false
        end

        # Send an event to the stream
        #
        # @param event_type [String] Event type
        # @param data [Object] Event data
        #
        def event(event_type, data)
          return if @closed
          @events << SSE.serialize_event(event_type, data)
        end

        def close
          @closed = true
        end

        def closed?
          @closed
        end
      end

      # Rack body that yields pre-collected events
      #
      # Implements the Rack body interface (#each, #close).
      #
      class BufferedBody
        def initialize(events)
          @events = events
        end

        def each
          @events.each { |event| yield event }
        end

        def close
        end
      end
    end
  end
end
