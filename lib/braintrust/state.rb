# frozen_string_literal: true

require_relative "api/internal/auth"

module Braintrust
  # State object that holds Braintrust configuration
  # Thread-safe global state management
  class State
    attr_reader :api_key, :org_name, :org_id, :default_project, :app_url, :api_url, :proxy_url, :logged_in

    @mutex = Mutex.new
    @global_state = nil

    def initialize(api_key: nil, org_name: nil, org_id: nil, default_project: nil, app_url: nil, api_url: nil, proxy_url: nil, logged_in: false)
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
      @logged_in = logged_in
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
  end
end
