# frozen_string_literal: true

# Start SimpleCov BEFORE loading any code to track
# Skip coverage when running under appraisal (different dependency scenarios)
unless ENV["BUNDLE_GEMFILE"]&.include?("gemfiles/")
  require "simplecov"

  SimpleCov.start do
    add_filter "/test/"
    enable_coverage :branch
    # TODO: Re-enable minimum coverage requirement once we reach 80%
    # minimum_coverage line: 80, branch: 80
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "braintrust"

require "minitest/autorun"
require "minitest/stub_const"
require "minitest/stub_any_instance"

# Show test timings when MT_VERBOSE is set
if ENV["MT_VERBOSE"]
  require "minitest/reporters"
  Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
end

# VCR for recording/replaying HTTP interactions
require "vcr"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = "test/fixtures/vcr_cassettes"
  config.hook_into :webmock

  # Filter sensitive data from cassettes
  # Note: We filter the API keys themselves, but NOT the Authorization header
  # because VCR needs the actual header value to replay requests correctly
  config.filter_sensitive_data("<BRAINTRUST_API_KEY>") { ENV["BRAINTRUST_API_KEY"] }
  config.filter_sensitive_data("<OPENAI_API_KEY>") { ENV["OPENAI_API_KEY"] }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }

  # Ignore OpenTelemetry trace exports (background async calls)
  config.ignore_request do |request|
    URI(request.uri).path.start_with?("/otel/")
  end

  # Explicitly block real HTTP connections by default
  # Only allow real requests when VCR_OFF=true (for debugging)
  config.allow_http_connections_when_no_cassette = ENV["VCR_OFF"] == "true"

  # Recording mode: :once (default), :all (re-record), :none (no recording)
  config.default_cassette_options = {
    record: ENV["VCR_MODE"]&.to_sym || :once,
    match_requests_on: [:method, :uri],  # Don't match on body (contains dynamic data)
    allow_playback_repeats: true  # Allow same HTTP interaction to be replayed multiple times
  }
end

# Disable VCR entirely if VCR_OFF is set
if ENV["VCR_OFF"]
  VCR.turn_off!(ignore_cassettes: true)
  WebMock.allow_net_connect!
end

# Test helpers for OpenTelemetry tracing
module TracingTestHelper
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

  # Wrapper for OpenTelemetry test setup
  class OtelTestRig
    attr_reader :tracer_provider, :exporter, :state

    def initialize(tracer_provider, exporter, state)
      @tracer_provider = tracer_provider
      @exporter = exporter
      @state = state
    end

    # Get a tracer from the provider
    # @param name [String] tracer name (default: "test")
    # @return [OpenTelemetry::Trace::Tracer]
    def tracer(name = "test")
      @tracer_provider.tracer(name)
    end

    # Flush and drain all spans from the exporter
    # @return [Array<OpenTelemetry::SDK::Trace::SpanData>]
    def drain
      @tracer_provider.force_flush
      spans = @exporter.finished_spans
      @exporter.reset
      spans
    end

    # Flush and drain exactly one span from the exporter
    # Asserts that exactly one span was flushed
    # @return [OpenTelemetry::SDK::Trace::SpanData]
    def drain_one
      spans = drain
      raise Minitest::Assertion, "Expected exactly 1 span, got #{spans.length}" unless spans.length == 1
      spans.first
    end
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

  # Sets up OpenTelemetry with an in-memory exporter for testing
  # Returns an OtelTestRig with tracer_provider, exporter, state, and drain() method
  # The exporter can be passed to Braintrust::Trace.enable to replace OTLP exporter
  # @param state_options [Hash] Options to pass to get_unit_test_state
  # @return [OtelTestRig]
  def setup_otel_test_rig(**state_options)
    require "opentelemetry/sdk"

    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    state = get_unit_test_state(**state_options)

    # Add Braintrust span processor (wraps simple processor with memory exporter)
    simple_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
    braintrust_processor = Braintrust::Trace::SpanProcessor.new(simple_processor, state)
    tracer_provider.add_span_processor(braintrust_processor)

    OtelTestRig.new(tracer_provider, exporter, state)
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

  # Generate unique name for parallel test runs
  # Returns: "ruby-sdk-test--prefix-d3adb33f" (8 hex chars of entropy)
  # @param prefix [String] optional prefix for the name
  # @return [String] unique name safe for parallel execution
  def unique_name(prefix = "")
    require "securerandom"
    entropy = SecureRandom.hex(4) # 8 hex chars
    if prefix.empty?
      "ruby-sdk-test--#{entropy}"
    else
      "ruby-sdk-test--#{prefix}-#{entropy}"
    end
  end

  # Stub login_in_thread to prevent background thread from spawning.
  # Asserts that login_in_thread would have been called.
  # Yields to the block for actual test code.
  # @yield Block containing the test code
  def mock_login_in_thread
    login_in_thread_called = false

    Braintrust::State.stub_any_instance(:login_in_thread, -> { login_in_thread_called = true }) do
      yield
    end

    assert login_in_thread_called, "Expected login_in_thread to be called"
  end

  # Get API key for tests
  # Uses real key for recording, fake key for playback
  # @return [String] API key
  def get_braintrust_key
    key = ENV["BRAINTRUST_API_KEY"]
    # In forked PRs, secrets may be empty strings
    key = nil if key&.empty?
    key || "test-key-for-vcr"
  end

  def get_openai_key
    ENV["OPENAI_API_KEY"] || "sk-test-key-for-vcr"
  end

  # Get Anthropic API key for tests
  # Uses real key for recording, fake key for playback
  # @return [String] API key
  def get_anthropic_key
    ENV["ANTHROPIC_API_KEY"] || "sk-ant-test-key-for-vcr"
  end

  # Build a chain of mocks for nested method calls.
  # Useful for testing code that traverses object hierarchies like `obj.foo.bar.baz`.
  #
  # Creates intermediate mocks that return each other in sequence, with the final
  # mock returning the specified terminal value. All intermediate mocks are verified
  # after the block. The caller is responsible for verifying the terminal value if needed.
  #
  # @param methods [Array<Symbol>] chain of method names to mock
  # @param returns [Object] the value returned by the final method (can be a Class, Mock, or any object)
  # @yield [root] the root mock (entry point to the chain)
  #
  # @example Testing a method chain with a Class as terminal
  #   fake_singleton = Class.new { include SomeModule }
  #   mock_chain(:chat, :completions, :singleton_class, returns: fake_singleton) do |client|
  #     assert SomePatcher.patched?(target: client)
  #   end
  #
  # @example Testing a method chain with a Mock as terminal
  #   terminal = Minitest::Mock.new
  #   terminal.expect(:include, true, [SomeModule])
  #   mock_chain(:foo, :bar, returns: terminal) do |root|
  #     SomeCode.do_something(root)
  #   end
  #   terminal.verify
  #
  def mock_chain(*methods, returns:)
    current = returns
    mocks = []

    methods.reverse_each do |method|
      mock = Minitest::Mock.new
      mock.expect(method, current)
      mocks.unshift(mock)
      current = mock
    end

    yield(mocks.first)

    mocks.each(&:verify)
  end
end

# Include helper in all test cases
class Minitest::Test
  include TracingTestHelper

  # Use Minitest hooks to clear global state after every test
  # This ensures cleanup happens even if individual tests don't have teardown methods
  def after_teardown
    Braintrust::State.instance_variable_set(:@global_state, nil)
    super
  end
end
