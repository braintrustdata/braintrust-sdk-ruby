# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require_relative "../logger"

module Braintrust
  module API
    module Auth
      # Result of a successful login
      AuthResult = Struct.new(:org_id, :org_name, :api_url, :proxy_url, keyword_init: true)

      # Mask API key for logging (show first 8 chars)
      def self.mask_api_key(api_key)
        return "nil" if api_key.nil?
        return api_key if api_key.length <= 8
        "#{api_key[0...8]}...#{api_key[-4..]}"
      end

      # Login to Braintrust API
      # @param api_key [String] Braintrust API key
      # @param app_url [String] Braintrust app URL
      # @param org_name [String, nil] Optional org name to filter by
      # @return [AuthResult] org info
      # @raise [Braintrust::Error] if login fails
      def self.login(api_key:, app_url:, org_name: nil)
        masked_key = mask_api_key(api_key)
        Log.debug("Login: attempting login with API key #{masked_key}, org #{org_name.inspect}, app URL #{app_url}")

        uri = URI("#{app_url}/api/apikey/login")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_key}"

        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true if uri.scheme == "https"

        response = http.start do |http_session|
          http_session.request(request)
        end

        Log.debug("Login: received response [#{response.code}]")

        # Handle different status codes
        case response
        when Net::HTTPUnauthorized, Net::HTTPForbidden
          raise Error, "Invalid API key: [#{response.code}]"
        when Net::HTTPBadRequest
          raise Error, "Bad request: [#{response.code}] #{response.body}"
        when Net::HTTPClientError
          raise Error, "Client error: [#{response.code}] #{response.message}"
        when Net::HTTPServerError
          raise Error, "Server error: [#{response.code}] #{response.message}"
        when Net::HTTPSuccess
          # Success - continue processing
        else
          raise Error, "Unexpected response: [#{response.code}] #{response.message}"
        end

        data = JSON.parse(response.body)
        org_info_list = data["org_info"]

        if org_info_list.nil? || org_info_list.empty?
          raise Error, "No organizations found for API key"
        end

        # Select org: filter by org_name if present, else take first
        org_info = if org_name
          found = org_info_list.find { |org| org["name"] == org_name }
          if found
            Log.debug("Login: selected org '#{org_name}' (id: #{found["id"]})")
            found
          else
            available = org_info_list.map { |o| o["name"] }.join(", ")
            raise Error, "Organization '#{org_name}' not found. Available: #{available}"
          end
        else
          selected = org_info_list.first
          Log.debug("Login: selected first org '#{selected["name"]}' (id: #{selected["id"]})")
          selected
        end

        result = AuthResult.new(
          org_id: org_info["id"],
          org_name: org_info["name"],
          api_url: org_info["api_url"],
          proxy_url: org_info["proxy_url"]
        )

        Log.debug("Login: successfully logged in as org '#{result.org_name}' (#{result.org_id})")
        result
      end
    end
  end
end
