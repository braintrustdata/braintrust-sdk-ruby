# frozen_string_literal: true

module Braintrust
  module Server
    # Rack-compatible response body that streams SSE events via `each`.
    #
    # Works with Puma (immediate writes), Passenger, and rack-test.
    # WEBrick buffers the entire body and is unsuitable for SSE.
    #
    # Falcon buffers `each`-based bodies as Enumerable; use SSEStreamBody instead.
    class SSEBody
      def initialize(&block)
        @block = block
      end

      def each
        writer = SSEWriter.new { |chunk| yield chunk }
        @block.call(writer)
      end
    end

    # Rack 3 streaming response body that writes SSE events via `call(stream)`.
    #
    # Required for servers using the protocol-rack adapter (e.g. Falcon), which
    # dispatches `each`-based bodies through a buffered Enumerable path. Bodies
    # that respond only to `call` are dispatched through the Streaming path for
    # true async writes.
    class SSEStreamBody
      def initialize(&block)
        @block = block
      end

      def call(stream)
        writer = SSEWriter.new { |chunk| stream.write(chunk) }
        @block.call(writer)
      ensure
        stream.close
      end
    end

    # Writes formatted SSE events.
    class SSEWriter
      def initialize(&block)
        @write = block
      end

      def event(type, data = "")
        @write.call("event: #{type}\ndata: #{data}\n\n")
      end
    end
  end
end
