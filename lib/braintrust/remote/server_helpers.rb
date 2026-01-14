# frozen_string_literal: true

module Braintrust
  module Remote
    # Helper methods and constants for building Braintrust evaluation servers
    #
    # This module provides server-agnostic utilities for:
    # - CORS header configuration
    # - Origin validation for Braintrust playground
    # - Authentication token extraction
    # - Evaluator list formatting
    #
    # These helpers work with any Ruby web framework (Rails, Sinatra, Rack, etc.)
    #
    # @example CORS headers in a controller
    #   response.headers.merge!(ServerHelpers::CORS.headers_for_origin(request.origin))
    #
    # @example Extract auth token
    #   token = ServerHelpers::Auth.extract_token(request.headers)
    #
    # @example Format evaluators for /list endpoint
    #   json = ServerHelpers.format_evaluator_list(Braintrust::Remote.evaluators)
    #
    module ServerHelpers
      # CORS configuration for Braintrust playground integration
      module CORS
        # Standard Braintrust origins that should be allowed
        ALLOWED_ORIGINS = [
          "https://www.braintrust.dev",
          "https://www.braintrustdata.com"
        ].freeze

        # Regex patterns for dynamic Braintrust origins (preview environments)
        ALLOWED_ORIGIN_PATTERNS = [
          /\Ahttps:\/\/.*\.preview\.braintrust\.dev\z/,
          /\Ahttps:\/\/.*\.vercel\.app\z/
        ].freeze

        # Headers allowed in requests from the playground
        ALLOWED_HEADERS = %w[
          Content-Type
          X-Amz-Date
          Authorization
          X-Api-Key
          X-Amz-Security-Token
          x-bt-auth-token
          x-bt-parent
          x-bt-org-name
          x-bt-project-id
          x-bt-stream-fmt
          x-bt-use-cache
          x-stainless-os
          x-stainless-lang
          x-stainless-package-version
          x-stainless-runtime
          x-stainless-runtime-version
          x-stainless-arch
        ].freeze

        # Headers exposed to the client
        EXPOSED_HEADERS = %w[
          x-bt-cursor
          x-bt-found-existing-experiment
          x-bt-span-id
          x-bt-span-export
        ].freeze

        # Allowed HTTP methods
        ALLOWED_METHODS = %w[GET POST PUT PATCH DELETE OPTIONS].freeze

        # Max age for preflight caching (24 hours)
        MAX_AGE = 86_400

        # Check if an origin is allowed
        #
        # @param origin [String, nil] The origin header value
        # @return [Boolean] True if the origin is allowed
        #
        def self.allowed_origin?(origin)
          return true if origin.nil? || origin.empty?

          # Check environment variable overrides
          whitelisted = ENV["WHITELISTED_ORIGIN"]
          return true if whitelisted && origin == whitelisted

          app_url = ENV["BRAINTRUST_APP_URL"]
          return true if app_url && origin == app_url

          # Check static allowed origins
          return true if ALLOWED_ORIGINS.include?(origin)

          # Check regex patterns
          return true if ALLOWED_ORIGIN_PATTERNS.any? { |p| p.match?(origin) }

          # Allow localhost for development
          return true if origin.start_with?("http://localhost:", "http://127.0.0.1:")

          false
        end

        # Get CORS headers for a given origin
        #
        # @param origin [String, nil] The request origin
        # @param include_private_network [Boolean] Whether to include PNA header
        # @return [Hash] CORS headers to add to the response
        #
        def self.headers_for_origin(origin, include_private_network: false)
          headers = {
            "Access-Control-Allow-Methods" => ALLOWED_METHODS.join(", "),
            "Access-Control-Allow-Headers" => ALLOWED_HEADERS.join(", "),
            "Access-Control-Expose-Headers" => EXPOSED_HEADERS.join(", "),
            "Access-Control-Max-Age" => MAX_AGE.to_s
          }

          if origin && allowed_origin?(origin)
            headers["Access-Control-Allow-Origin"] = origin
            headers["Access-Control-Allow-Credentials"] = "true"
          else
            headers["Access-Control-Allow-Origin"] = "*"
          end

          # Chrome Private Network Access support
          if include_private_network
            headers["Access-Control-Allow-Private-Network"] = "true"
          end

          headers
        end

        # Get all CORS headers as a formatted string for raw socket responses
        #
        # @param origin [String, nil] The request origin
        # @return [String] CORS headers formatted for HTTP response
        #
        def self.headers_string(origin)
          hdrs = headers_for_origin(origin)
          hdrs.map { |k, v| "#{k}: #{v}" }.join("\r\n")
        end
      end

      # Authentication helpers
      module Auth
        # Header names for authentication (normalized for different frameworks)
        TOKEN_HEADERS = %w[
          HTTP_X_BT_AUTH_TOKEN
          X-Bt-Auth-Token
          x-bt-auth-token
        ].freeze

        AUTH_HEADERS = %w[
          HTTP_AUTHORIZATION
          Authorization
          authorization
        ].freeze

        # Extract authentication token from headers
        #
        # @param headers [Hash] Request headers (can be Rack env or plain hash)
        # @return [String, nil] The extracted token, or nil if not found
        #
        # @example With Rack env
        #   token = Auth.extract_token(request.env)
        #
        # @example With plain headers hash
        #   token = Auth.extract_token({ "x-bt-auth-token" => "sk-..." })
        #
        def self.extract_token(headers)
          # Try x-bt-auth-token header first
          TOKEN_HEADERS.each do |key|
            token = headers[key]
            return token if token && !token.empty?
          end

          # Fall back to Authorization: Bearer token
          AUTH_HEADERS.each do |key|
            auth_header = headers[key]
            if auth_header&.start_with?("Bearer ")
              return auth_header.sub("Bearer ", "")
            end
          end

          nil
        end

        # Extract org name from headers
        #
        # @param headers [Hash] Request headers
        # @return [String, nil] The org name, or nil if not found
        #
        def self.extract_org_name(headers)
          headers["HTTP_X_BT_ORG_NAME"] ||
            headers["X-Bt-Org-Name"] ||
            headers["x-bt-org-name"]
        end

        # Extract project ID from headers
        #
        # @param headers [Hash] Request headers
        # @return [String, nil] The project ID, or nil if not found
        #
        def self.extract_project_id(headers)
          headers["HTTP_X_BT_PROJECT_ID"] ||
            headers["X-Bt-Project-Id"] ||
            headers["x-bt-project-id"]
        end
      end

      # Format an evaluator for the /list endpoint response
      #
      # @param evaluator [Evaluator] The evaluator to format
      # @return [Hash] Formatted evaluator data
      #
      def self.format_evaluator(evaluator)
        {
          parameters: evaluator.parameters_to_json_schema,
          scores: evaluator.scorer_info
        }
      end

      # Format all evaluators for the /list endpoint response
      #
      # @param evaluators [Hash<String, Evaluator>] Map of name -> evaluator
      # @return [Hash] Formatted response for /list endpoint
      #
      def self.format_evaluator_list(evaluators)
        evaluators.transform_values { |eval| format_evaluator(eval) }
      end

      # Parse the parent object from request body
      # When running from the playground, a parent object is provided
      #
      # @param body [Hash] The parsed request body
      # @return [Hash, nil] The parent object, or nil
      #
      def self.extract_parent(body)
        body["parent"]
      end

      # Check if this is a playground request (has parent)
      #
      # @param body [Hash] The parsed request body
      # @return [Boolean] True if running from playground
      #
      def self.playground_request?(body)
        !body["parent"].nil?
      end
    end
  end
end
