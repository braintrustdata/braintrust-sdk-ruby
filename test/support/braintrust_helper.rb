module Test
  module Support
    module BraintrustHelper
      # =============================================================================
      # IMPORTANT: Magic Test API Key
      # =============================================================================
      #
      # When calling Braintrust.init in tests, use api_key: "test-api-key" to trigger
      # fake authentication that avoids HTTP requests. This magic key is handled in
      # lib/braintrust/api/internal/auth.rb and returns fake org info immediately.
      #
      # Without this magic key, Braintrust.init spawns a background login thread that
      # can cause WebMock errors after tests complete (orphan thread race condition).
      #
      # Example:
      #   Braintrust.init(api_key: "test-api-key", set_global: false, enable_tracing: true)
      #
      # TODO: Future work - move this magic key handling out of production code and into
      # test helpers instead. Options include:
      #   1. A test-only initializer that provides org_id directly (skips login entirely)
      #   2. Dependency injection for the Auth module in tests
      #   3. Environment-based test mode detection
      #
      # See: lib/braintrust/api/internal/auth.rb for the magic key implementation
      # =============================================================================
      # Get API key for tests
      # Uses real key for recording, fake key for playback
      # @return [String] API key
      def get_braintrust_key
        key = ENV["BRAINTRUST_API_KEY"]
        # In forked PRs, secrets may be empty strings
        key = nil if key&.empty?
        key || "test-key-for-vcr"
      end

      # Creates a test State for unit tests (no login, no API calls)
      # Override any fields by passing options
      # Note: Providing org_id skips the login thread automatically
      # @return [Braintrust::State]
      def get_unit_test_state(**options)
        defaults = {
          api_key: "test-key",
          api_url: "https://api.example.com",
          app_url: "https://app.example.com",
          org_name: "test-org",
          org_id: "test-org-id",
          default_project: "test-project",
          enable_tracing: false
        }

        state = Braintrust::State.new(**defaults.merge(options))
        state.validate
        state
      end

      # Creates a State for integration tests (performs login via VCR)
      # This performs login (via VCR cassettes in tests) without polluting global state
      # Use this for tests that need to interact with the API (eval, experiments, datasets, etc.)
      # @param options [Hash] Options to pass to Braintrust.init (set_global and blocking_login are fixed)
      # @return [Braintrust::State]
      def get_integration_test_state(**options)
        # Provide fallback API key for VCR playback (empty in forked PRs)
        options[:api_key] ||= get_braintrust_key
        Braintrust.init(set_global: false, blocking_login: true, **options)
      end

      # Creates an API client for integration tests (without polluting global state)
      # This is the preferred way to get an API client for tests.
      # @param options [Hash] Options to pass to get_integration_test_state
      # @return [Braintrust::API]
      def get_integration_test_api(**options)
        state = get_integration_test_state(**options)
        Braintrust::API.new(state: state)
      end

      # Helper to run eval internally without API calls for testing
      def run_test_eval(experiment_id:, experiment_name:, project_id:, project_name:,
        cases:, task:, scorers:, state:, parallelism: 1, tracer_provider: nil)
        runner = Braintrust::Eval::Runner.new(
          experiment_id: experiment_id,
          experiment_name: experiment_name,
          project_id: project_id,
          project_name: project_name,
          task: task,
          scorers: scorers,
          state: state,
          tracer_provider: tracer_provider
        )
        runner.run(cases, parallelism: parallelism)
      end
    end
  end
end
