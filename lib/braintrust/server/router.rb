# frozen_string_literal: true

require "json"

module Braintrust
  module Server
    # Simple request router that dispatches to handlers based on method + path.
    # Returns 405 for known paths with wrong method, 404 for unknown paths.
    class Router
      def initialize
        @routes = {}
      end

      def add(method, path, handler)
        @routes["#{method} #{path}"] = handler
        self
      end

      def call(env)
        method = env["REQUEST_METHOD"]
        path = env["PATH_INFO"]

        handler = @routes["#{method} #{path}"]
        return handler.call(env) if handler

        # Path exists but wrong method
        if @routes.any? { |key, _| key.end_with?(" #{path}") }
          return [405, {"content-type" => "application/json"},
            [JSON.dump({"error" => "Method not allowed"})]]
        end

        [404, {"content-type" => "application/json"},
          [JSON.dump({"error" => "Not found"})]]
      end
    end
  end
end
