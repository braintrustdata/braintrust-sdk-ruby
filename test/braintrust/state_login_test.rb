# frozen_string_literal: true

require "test_helper"

class Braintrust::StateLoginTest < Minitest::Test
  def setup
    @api_key = ENV["BRAINTRUST_API_KEY"]
    assert @api_key, "BRAINTRUST_API_KEY environment variable is required for login tests"
  end

  def teardown
    Braintrust::State.instance_variable_set(:@global_state, nil)
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
    VCR.use_cassette("auth/login_with_retries") do
      state = Braintrust::State.new(
        api_key: @api_key,
        app_url: "https://www.braintrust.dev"
      )

      # Track how many times Auth.login is called
      call_count = 0
      original_login = Braintrust::API::Internal::Auth.method(:login)

      # Stub Auth.login to fail twice, then succeed
      Braintrust::API::Internal::Auth.define_singleton_method(:login) do |**args|
        call_count += 1
        if call_count <= 2
          raise Braintrust::Error, "Simulated network error"
        else
          original_login.call(**args)
        end
      end

      begin
        # Start background login
        state.login_in_thread

        # Wait for it to complete (should retry and eventually succeed)
        state.wait_for_login(30)

        # Should have retried and succeeded
        assert state.logged_in, "State should be logged in after wait_for_login, but logged_in=#{state.logged_in}, call_count=#{call_count}"
        assert call_count >= 3, "Expected at least 3 login attempts, got #{call_count}"
      ensure
        # Restore original method
        Braintrust::API::Internal::Auth.define_singleton_method(:login, original_login)
      end
    end
  end

  def test_login_in_thread_returns_early_if_already_logged_in
    VCR.use_cassette("auth/login_idempotent") do
      state = Braintrust::State.new(
        api_key: @api_key,
        app_url: "https://www.braintrust.dev"
      )

      # Log in first (blocking)
      state.login
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
      state.wait_for_login(30)

      # Should be logged in exactly once (not multiple times)
      assert state.logged_in
      refute_nil state.org_id
    end
  end
end
