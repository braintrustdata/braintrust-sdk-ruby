# frozen_string_literal: true

module Braintrust
  module Server
    # Rack-compatible response body that streams SSE events.
    # Works with both streaming servers (Puma, Falcon) and buffered responses (rack-test).
    class SSEBody
      def initialize(&block)
        @block = block
      end

      def each
        writer = SSEWriter.new { |chunk| yield chunk }
        @block.call(writer)
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
