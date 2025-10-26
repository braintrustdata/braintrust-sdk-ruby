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

  # Allow real requests when VCR_OFF=true (for debugging)
  config.allow_http_connections_when_no_cassette = true if ENV["VCR_OFF"]

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
      @exporter.finished_spans
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

  # Creates a test State with sensible defaults and validates it
  # Override any fields by passing options
  # @return [Braintrust::State]
  def get_test_state(**options)
    defaults = {
      api_key: "test-key",
      api_url: "https://api.example.com",
      app_url: "https://app.example.com",
      org_name: "test-org",
      default_project: "test-project"
    }

    state = Braintrust::State.new(**defaults.merge(options))
    state.validate
    state
  end

  # Creates a non-global State by calling Braintrust.init with set_global: false and blocking_login: true
  # This performs login (via VCR cassettes in tests) without polluting global state
  # Use this for tests that need to interact with the API (eval, experiments, datasets, etc.)
  # @param options [Hash] Options to pass to Braintrust.init (set_global and blocking_login are fixed)
  # @return [Braintrust::State]
  def get_non_global_state(**options)
    Braintrust.init(set_global: false, blocking_login: true, **options)
  end

  # Sets up OpenTelemetry with an in-memory exporter for testing
  # Returns an OtelTestRig with tracer_provider, exporter, state, and drain() method
  # The exporter can be passed to Braintrust::Trace.enable to replace OTLP exporter
  # @param state_options [Hash] Options to pass to get_test_state
  # @return [OtelTestRig]
  def setup_otel_test_rig(**state_options)
    require "opentelemetry/sdk"

    exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    state = get_test_state(**state_options)

    # Add Braintrust span processor (wraps simple processor with memory exporter)
    simple_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
    braintrust_processor = Braintrust::Trace::SpanProcessor.new(simple_processor, state)
    tracer_provider.add_span_processor(braintrust_processor)

    OtelTestRig.new(tracer_provider, exporter, state)
  end

  # Helper to run eval internally without API calls for testing
  # Wraps the private run_internal method
  def run_test_eval(**kwargs)
    Braintrust::Eval.send(:run_internal, **kwargs)
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
