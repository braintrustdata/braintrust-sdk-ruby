# frozen_string_literal: true

require_relative "api/internal/auth"

module Braintrust
  # State object that holds Braintrust configuration
  # Thread-safe global state management
  class State
    attr_reader :api_key, :org_name, :org_id, :default_project, :app_url, :api_url, :proxy_url, :logged_in, :autoinstrument_config

    @mutex = Mutex.new
    @global_state = nil

    # Create a State from environment variables with option overrides
    # @param api_key [String, nil] Braintrust API key (overrides BRAINTRUST_API_KEY env var)
    # @param org_name [String, nil] Organization name (overrides BRAINTRUST_ORG_NAME env var)
    # @param default_project [String, nil] Default project (overrides BRAINTRUST_DEFAULT_PROJECT env var)
    # @param app_url [String, nil] App URL (overrides BRAINTRUST_APP_URL env var)
    # @param api_url [String, nil] API URL (overrides BRAINTRUST_API_URL env var)
    # @param blocking_login [Boolean] whether to block and login synchronously (default: false)
    # @param enable_tracing [Boolean] whether to enable OpenTelemetry tracing (default: true)
    # @param tracer_provider [TracerProvider, nil] Optional tracer provider to use
    # @param autoinstrument [Hash, nil] Auto-instrumentation configuration (default: nil)
    # @return [State] the created state
    def self.from_env(api_key: nil, org_name: nil, default_project: nil, app_url: nil, api_url: nil, blocking_login: false, enable_tracing: true, tracer_provider: nil, autoinstrument: nil)
      require_relative "config"
      config = Config.from_env(
        api_key: api_key,
        org_name: org_name,
        default_project: default_project,
        app_url: app_url,
        api_url: api_url
      )
      new(
        api_key: config.api_key,
        org_name: config.org_name,
        default_project: config.default_project,
        app_url: config.app_url,
        api_url: config.api_url,
        blocking_login: blocking_login,
        enable_tracing: enable_tracing,
        tracer_provider: tracer_provider,
        autoinstrument: autoinstrument
      )
    end

    def initialize(api_key: nil, org_name: nil, org_id: nil, default_project: nil, app_url: nil, api_url: nil, proxy_url: nil, blocking_login: false, enable_tracing: true, tracer_provider: nil, autoinstrument: nil)
      # Instance-level mutex for thread-safe login
      @login_mutex = Mutex.new
      raise ArgumentError, "api_key is required" if api_key.nil? || api_key.empty?

      @api_key = api_key
      @org_name = org_name
      @org_id = org_id
      @default_project = default_project
      @app_url = app_url || "https://www.braintrust.dev"
      @api_url = api_url
      @proxy_url = proxy_url
      @logged_in = false

      # Parse and validate autoinstrument config
      @autoinstrument_config = parse_autoinstrument_config(autoinstrument)

      # Perform login after state setup
      if blocking_login
        login
      else
        login_in_thread
      end

      # Setup tracing if requested
      if enable_tracing
        require_relative "trace"
        Trace.setup(self, tracer_provider)
      end
    end

    # Thread-safe global state getter
    def self.global
      @mutex.synchronize { @global_state }
    end

    # Thread-safe global state setter
    def self.global=(state)
      @mutex.synchronize { @global_state = state }
    end

    # Login to Braintrust API and update state with org info
    # Makes synchronous HTTP request via API::Auth
    # Updates @org_id, @org_name, @api_url, @proxy_url, @logged_in
    # Idempotent: returns early if already logged in
    # Thread-safe: protected by mutex
    # @return [self]
    def login
      @login_mutex.synchronize do
        # Return early if already logged in
        return self if @logged_in

        result = API::Internal::Auth.login(
          api_key: @api_key,
          app_url: @app_url,
          org_name: @org_name
        )

        # Update state with org info
        @org_id = result.org_id
        @org_name = result.org_name
        @api_url = result.api_url
        @proxy_url = result.proxy_url
        @logged_in = true

        self
      end
    end

    # Login to Braintrust API in a background thread with retry logic
    # Retries indefinitely with exponential backoff until success
    # Idempotent: returns early if already logged in
    # Thread-safe: login method is protected by mutex
    # @return [self]
    def login_in_thread
      # Return early if already logged in (without spawning thread)
      return self if @logged_in

      @login_thread = Thread.new do
        retry_count = 0
        max_delay = 5.0

        loop do
          Log.debug("Background login attempt #{retry_count + 1}")
          login
          Log.debug("Background login succeeded")
          break
        rescue => e
          retry_count += 1
          delay = [0.001 * 2**(retry_count - 1), max_delay].min
          Log.debug("Background login failed (attempt #{retry_count}): #{e.message}. Retrying in #{delay}s...")
          sleep delay
        end
      end

      self
    end

    # Wait for background login thread to complete (for testing)
    # @param timeout [Numeric, nil] Optional timeout in seconds
    # @return [self]
    def wait_for_login(timeout = nil)
      @login_thread&.join(timeout)
      self
    end

    # Validate state is properly configured
    # Raises ArgumentError if state is invalid
    # @return [self]
    def validate
      raise ArgumentError, "api_key is required" if @api_key.nil? || @api_key.empty?
      raise ArgumentError, "api_url is required" if @api_url.nil? || @api_url.empty?
      raise ArgumentError, "app_url is required" if @app_url.nil? || @app_url.empty?

      # If logged_in is true, org_id and org_name should be present
      if @logged_in
        raise ArgumentError, "org_id is required when logged_in is true" if @org_id.nil? || @org_id.empty?
        raise ArgumentError, "org_name is required when logged_in is true" if @org_name.nil? || @org_name.empty?
      end

      self
    end

    private

    # Parse and validate autoinstrument configuration
    # @param config [Hash, nil] Raw autoinstrument config from user
    # @return [Hash] Normalized and validated config
    def parse_autoinstrument_config(config)
      # Default: disabled
      return {enabled: false} if config.nil?

      # Explicit disabled
      return {enabled: false} if config[:enabled] == false

      # Validation: include and exclude cannot both be present
      if config[:include] && config[:exclude]
        raise ArgumentError, "Cannot specify both :include and :exclude in autoinstrument config"
      end

      # Validation: include/exclude require enabled: true
      if config[:include] && config[:enabled] != true
        raise ArgumentError, ":include requires :enabled to be true in autoinstrument config"
      end

      if config[:exclude] && config[:enabled] != true
        raise ArgumentError, ":exclude requires :enabled to be true in autoinstrument config"
      end

      # Validation: include must be an array
      if config[:include] && !config[:include].is_a?(Array)
        raise ArgumentError, ":include must be an array in autoinstrument config"
      end

      # Validation: exclude must be an array
      if config[:exclude] && !config[:exclude].is_a?(Array)
        raise ArgumentError, ":exclude must be an array in autoinstrument config"
      end

      # Validation: include values must be symbols
      if config[:include] && !config[:include].all? { |v| v.is_a?(Symbol) }
        raise ArgumentError, ":include must contain only symbols in autoinstrument config"
      end

      # Validation: exclude values must be symbols
      if config[:exclude] && !config[:exclude].all? { |v| v.is_a?(Symbol) }
        raise ArgumentError, ":exclude must contain only symbols in autoinstrument config"
      end

      # Normalize enabled: true case
      {
        enabled: config[:enabled] == true,
        include: config[:include],
        exclude: config[:exclude]
      }
    end
  end
end
