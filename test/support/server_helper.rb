module Test
  module Support
    module ServerHelper
      # Parse an SSE event stream string into an array of {event:, data:} hashes.
      def parse_sse_events(text)
        events = []
        current_event = nil
        current_data = []

        text.each_line do |line|
          line = line.chomp
          if line.start_with?("event: ")
            current_event = line.sub("event: ", "")
          elsif line.start_with?("data: ")
            current_data << line.sub("data: ", "")
          elsif line.empty? && current_event
            events << {event: current_event, data: current_data.join("\n")}
            current_event = nil
            current_data = []
          end
        end

        if current_event
          events << {event: current_event, data: current_data.join("\n")}
        end

        events
      end

      # Collect SSE events from a Rack response body (enumerable of chunks).
      def collect_sse_events(body)
        full = +""
        body.each { |chunk| full << chunk }
        parse_sse_events(full)
      end

      # Build a minimal Rack env hash with an optional request body string.
      def rack_env_with_body(body_str, method: "POST", path: "/")
        env = {"REQUEST_METHOD" => method, "PATH_INFO" => path}
        if body_str
          env["rack.input"] = StringIO.new(body_str)
          env["CONTENT_TYPE"] = "application/json"
        else
          env["rack.input"] = StringIO.new("")
        end
        env
      end

      # Build a Rack env with a JSON-encoded hash body.
      def rack_json_env(hash, **opts)
        rack_env_with_body(JSON.dump(hash), **opts)
      end
    end
  end
end
