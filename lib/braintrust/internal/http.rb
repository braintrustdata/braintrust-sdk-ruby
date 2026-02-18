# frozen_string_literal: true

require "net/http"
require "uri"
require "zlib"
require "stringio"
require_relative "../logger"

module Braintrust
  module Internal
    # HTTP utilities for redirect following and response decompression.
    # Drop-in enhancement for raw Net::HTTP request calls throughout the SDK.
    module Http
      DEFAULT_MAX_REDIRECTS = 5

      # Execute an HTTP request, following redirects as needed.
      #
      # @param uri [URI] The request URI
      # @param request [Net::HTTPRequest] The prepared request object
      # @param max_redirects [Integer] Maximum number of redirects to follow
      # @return [Net::HTTPResponse] The final response
      # @raise [Braintrust::Error] On too many redirects or missing Location header
      def self.with_redirects(uri, request, max_redirects: DEFAULT_MAX_REDIRECTS)
        response = perform_request(uri, request)

        redirects = 0
        original_request = request

        while response.is_a?(Net::HTTPRedirection)
          redirects += 1
          if redirects > max_redirects
            raise Error, "Too many redirects (max #{max_redirects})"
          end

          location = response["location"]
          unless location
            raise Error, "Redirect response #{response.code} without Location header"
          end

          redirect_uri = URI(location)
          redirect_uri = uri + redirect_uri unless redirect_uri.host

          Log.debug("[HTTP] Following #{response.code} redirect to #{redirect_uri}")

          request = build_redirect_request(response, redirect_uri, original_request, uri)
          uri = redirect_uri
          response = perform_request(uri, request)
        end

        response
      end

      # Decompress an HTTP response body in place based on Content-Encoding.
      # No-op if the response has no recognized encoding.
      #
      # @param response [Net::HTTPResponse] The response to decompress
      # @return [void]
      def self.decompress_response!(response)
        encoding = response["content-encoding"]&.downcase
        case encoding
        when "gzip", "x-gzip"
          gz = Zlib::GzipReader.new(StringIO.new(response.body))
          response.body.replace(gz.read)
          gz.close
          response.delete("content-encoding")
        end
      end

      def self.perform_request(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.request(request)
      end
      private_class_method :perform_request

      def self.build_redirect_request(response, redirect_uri, original_request, original_uri)
        if response.code == "307" || response.code == "308"
          request = original_request.class.new(redirect_uri)
          request.body = original_request.body
          request["Content-Type"] = original_request["Content-Type"] if original_request["Content-Type"]
        else
          # 301, 302, 303: follow with GET, no body
          request = Net::HTTP::Get.new(redirect_uri)
        end

        # Strip Authorization when redirecting to a different host (e.g. S3)
        if original_uri.host == redirect_uri.host
          auth = original_request["Authorization"]
          request["Authorization"] = auth if auth
        end

        request
      end
      private_class_method :build_redirect_request
    end
  end
end
