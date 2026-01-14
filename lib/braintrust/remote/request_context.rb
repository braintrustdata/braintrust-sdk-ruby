# frozen_string_literal: true

module Braintrust
  module Remote
    # Context object for authenticated requests to the evaluation server
    #
    # This class holds the authentication context extracted from request headers,
    # along with the initialized State and API client. It's used by the handlers
    # to access Braintrust resources.
    #
    # @example Create context from headers (in middleware)
    #   ctx = RequestContext.new(
    #     token: "sk-...",
    #     org_name: "my-org",
    #     app_origin: "https://www.braintrust.dev",
    #     project_id: "proj-123"
    #   )
    #   ctx.login!  # Creates state and API client
    #
    # @example Use context in handlers
    #   if ctx.authorized?
    #     resolver = DataResolver.new(ctx.api)
    #     cases = resolver.resolve(data_spec)
    #   end
    #
    class RequestContext
      # @return [String] The authentication token (API key)
      attr_reader :token

      # @return [String] The organization name
      attr_reader :org_name

      # @return [String] The app origin URL
      attr_reader :app_origin

      # @return [String, nil] The project ID (optional)
      attr_reader :project_id

      # @return [Braintrust::State, nil] The Braintrust state (after login)
      attr_accessor :state

      # @return [Braintrust::API, nil] The API client (after login)
      attr_accessor :api

      # Create a new request context
      #
      # @param token [String] Authentication token (API key)
      # @param org_name [String] Organization name
      # @param app_origin [String, nil] App origin URL (default: https://www.braintrust.dev)
      # @param project_id [String, nil] Optional project ID
      #
      def initialize(token:, org_name:, app_origin: nil, project_id: nil)
        @token = token
        @org_name = org_name
        @app_origin = app_origin || "https://www.braintrust.dev"
        @project_id = project_id
        @state = nil
        @api = nil
        @authorized = false
      end

      # Check if the context has been authorized (logged in successfully)
      #
      # @return [Boolean] true if authorized
      #
      def authorized?
        @authorized
      end

      # Mark the context as authorized
      # Called after successful login
      #
      def mark_authorized!
        @authorized = true
      end

      # Perform login and create State and API client
      #
      # This method creates a Braintrust::State with blocking login,
      # then creates an API client using that state.
      #
      # @param enable_tracing [Boolean] Whether to enable tracing (default: false)
      # @return [self]
      # @raise [ArgumentError] If token is missing
      # @raise [Braintrust::Error] If login fails
      #
      def login!(enable_tracing: false)
        @state = Braintrust::State.new(
          api_key: @token,
          org_name: @org_name,
          app_url: @app_origin,
          blocking_login: true,
          enable_tracing: enable_tracing
        )

        @api = Braintrust::API.new(state: @state)
        mark_authorized!

        self
      end

      # Create a context from request headers and perform login
      #
      # @param headers [Hash] Request headers (Rack env or plain hash)
      # @param enable_tracing [Boolean] Whether to enable tracing (default: false)
      # @return [RequestContext] Authorized context
      # @raise [ArgumentError] If required headers are missing
      # @raise [Braintrust::Error] If login fails
      #
      # @example From Rack env
      #   ctx = RequestContext.from_headers(request.env)
      #
      def self.from_headers(headers, enable_tracing: false)
        token = ServerHelpers::Auth.extract_token(headers)
        raise ArgumentError, "Missing authentication token" unless token

        org_name = ServerHelpers::Auth.extract_org_name(headers)
        raise ArgumentError, "Missing x-bt-org-name header" unless org_name

        project_id = ServerHelpers::Auth.extract_project_id(headers)

        # Get origin and validate
        origin = headers["HTTP_ORIGIN"] || headers["Origin"]
        app_origin = ServerHelpers::CORS.allowed_origin?(origin) ? origin : nil

        ctx = new(
          token: token,
          org_name: org_name,
          app_origin: app_origin,
          project_id: project_id
        )

        ctx.login!(enable_tracing: enable_tracing)
        ctx
      end
    end
  end
end
