# frozen_string_literal: true

require "test_helper"

class Braintrust::StateLoginTest < Minitest::Test
  def setup
    # Use real key for recording, fake key for playback (VCR doesn't need real keys)
    # In forked PRs, secrets may be empty strings, so we check for both nil and empty
    @api_key = ENV["BRAINTRUST_API_KEY"]
    @api_key = "test-key-for-vcr" if @api_key.nil? || @api_key.empty?
  end

  def test_login_fetches_org_info
    VCR.use_cassette("auth/login_success") do
      state = Braintrust::State.new(
        api_key: @api_key,
        app_url: "https://www.braintrust.dev"
      )

      state.login

      assert state.logged_in
      refute_nil state.org_id
      refute_nil state.org_name
      refute_nil state.api_url
    end
  end

  def test_login_with_invalid_api_key
    VCR.use_cassette("auth/login_invalid_key") do
      state = Braintrust::State.new(
        api_key: "invalid-key",
        app_url: "https://www.braintrust.dev"
      )

      error = assert_raises(Braintrust::Error) do
        state.login
      end

      assert_match(/invalid api key/i, error.message)
    end
  end

  def test_login_in_thread_retries_on_failure
    # IMPORTANT: Disable VCR and set up stubs BEFORE creating State, because
    # State.new immediately spawns a background login thread when no org_id
    # is provided. If stubs aren't ready, the thread hits WebMock errors.
    VCR.turn_off!
    begin
      # Stub HTTP to fail twice, then succeed
      # This tests the real Auth.login code path and retry logic
      stub = stub_request(:post, "https://www.braintrust.dev/api/apikey/login")
        .to_return(
          {status: 500, body: "Internal Server Error"},
          {status: 500, body: "Internal Server Error"},
          {
            status: 200,
            body: JSON.generate({
              org_info: [{
                id: "test-org-id",
                name: "test-org",
                api_url: "https://api.braintrust.dev",
                proxy_url: "https://api.braintrust.dev"
              }]
            }),
            headers: {"Content-Type" => "application/json"}
          }
        )

      begin
        # Now create State - this spawns the login thread with stubs already in place
        state = Braintrust::State.new(
          api_key: @api_key,
          app_url: "https://www.braintrust.dev",
          enable_tracing: false
        )

        # Wait for it to complete (should retry and eventually succeed)
        state.wait_for_login(5)

        # Should have retried and succeeded
        assert state.logged_in, "State should be logged in after wait_for_login"
        assert_equal "test-org-id", state.org_id
        assert_equal "test-org", state.org_name

        # Verify we made at least 3 requests (2 failures + 1 success)
        assert_requested stub, at_least_times: 3
      ensure
        # Clean up the stub to prevent interference with other tests
        remove_request_stub(stub)
      end
    ensure
      # Re-enable VCR for other tests
      VCR.turn_on!
    end
  end

  def test_login_in_thread_returns_early_if_already_logged_in
    VCR.use_cassette("auth/login_idempotent") do
      # Create state with blocking_login to get logged-in state
      state = Braintrust::State.new(
        api_key: @api_key,
        app_url: "https://www.braintrust.dev",
        blocking_login: true,
        enable_tracing: false
      )

      assert state.logged_in

      # Track if Auth.login is called again
      called = false
      original_login = Braintrust::API::Internal::Auth.method(:login)
      Braintrust::API::Internal::Auth.define_singleton_method(:login) do |**args|
        called = true
        original_login.call(**args)
      end

      # Call login_in_thread - should return early without spawning thread
      state.login_in_thread
      state.wait_for_login(5)

      # Should not have called Auth.login again
      refute called, "Should not call Auth.login if already logged in"
    ensure
      Braintrust::API::Internal::Auth.define_singleton_method(:login, original_login)
    end
  end

  def test_login_in_thread_is_thread_safe
    VCR.use_cassette("auth/login_thread_safe") do
      state = Braintrust::State.new(
        api_key: @api_key,
        app_url: "https://www.braintrust.dev"
      )

      # Start multiple concurrent login_in_thread calls
      # Each call spawns an internal thread, but only one login should succeed
      5.times { state.login_in_thread }

      # Wait for login to complete
      state.wait_for_login(5)

      # Should be logged in exactly once (not multiple times)
      assert state.logged_in
      refute_nil state.org_id
    end
  end
end
