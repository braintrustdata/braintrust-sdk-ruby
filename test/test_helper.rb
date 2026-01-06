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
end

# Runs the test inside a fork, to isolate its side-effects from the main process.
# Similar in purpose to https://docs.ruby-lang.org/en/master/Ruby/Box.html#class-Ruby::Box
#
# Yields to the block for actual test code.
# @yield Block containing the test code
def assert_in_fork(fork_assertions: nil, timeout_seconds: 10, trigger_stacktrace_on_kill: false, debug: false)
  fork_assertions ||= proc { |status:, stdout:, stderr:|
    assert (status && status.success?), "STDOUT:`#{stdout}` STDERR:`#{stderr}"
  }

  if debug
    rv = assert_in_fork_debug(fork_assertions: fork_assertions) do
      yield
    end
    return rv
  end

  fork_stdout = Tempfile.new("braintrust-minitest-assert-in-fork-stdout")
  fork_stderr = Tempfile.new("braintrust-minitest-assert-in-fork-stderr")
  begin
    # Start in fork
    pid = fork do
      # Capture forked output
      $stdout.reopen(fork_stdout)
      $stdout.sync = true
      $stderr.reopen(fork_stderr) # STDERR captures failures. We print it in case the fork fails on exit.
      $stderr.sync = true

      yield
    end

    # Wait for fork to finish, retrieve its status.
    # Enforce timeout to ensure test fork doesn't hang the test suite.
    _, status = try_wait_until(seconds: timeout_seconds) { Process.wait2(pid, Process::WNOHANG) }

    stdout = File.read(fork_stdout.path)
    stderr = File.read(fork_stderr.path)

    # Capture forked execution information
    result = {status: status, stdout: stdout, stderr: stderr}

    # Check if fork and assertions have completed successfully
    fork_assertions.call(**result)

    result
  rescue => e
    crash_note = nil

    if trigger_stacktrace_on_kill
      crash_note = " (Crashing Ruby to get stacktrace as requested by `trigger_stacktrace_on_kill`)"
      begin
        Process.kill("SEGV", pid)
        warn "Waiting for child process to exit after SEGV signal... #{crash_note}"
        Process.wait(pid)
      rescue
        nil
      end
    end

    stdout = File.read(fork_stdout.path)
    stderr = File.read(fork_stderr.path)

    raise "Failure or timeout in `assert_in_fork`#{crash_note}, STDOUT: `#{stdout}`, STDERR: `#{stderr}`", cause: e
  ensure
    begin
      Process.kill("KILL", pid)
    rescue
      nil
    end # Prevent zombie processes on failure

    fork_stderr.close
    fork_stdout.close
    fork_stdout.unlink
    fork_stderr.unlink
  end
end

# Debug version of assert_in_fork that does not redirect I/O streams and
# has no timeout on execution. The idea is to use it for interactive
# debugging where you would set a break point in the fork.
def assert_in_fork_debug(fork_assertions:, timeout_seconds: 10, trigger_stacktrace_on_kill: false)
  pid = fork do
    yield
  end
  _, status = Process.wait2(pid)
  fork_assertions.call(status: status, stdout: "", stderr: "")
end

# Waits for the condition provided by the block argument to return truthy.
#
# Waits for 5 seconds by default.
#
# Can be configured by setting either:
#   * `seconds`, or
#   * `attempts` and `backoff`
#
# @yieldreturn [Boolean] block executed until it returns truthy
# @param [Numeric] seconds number of seconds to wait
# @param [Integer] attempts number of attempts at checking the condition
# @param [Numeric] backoff wait time between condition checking attempts
def try_wait_until(seconds: nil, attempts: nil, backoff: nil)
  raise "Provider either `seconds` or `attempts` & `backoff`, not both" if seconds && (attempts || backoff)

  spec = if seconds
    "#{seconds} seconds"
  elsif attempts || backoff
    "#{attempts} attempts with backoff: #{backoff}"
  else
    "none"
  end

  if seconds
    attempts = seconds * 10
    backoff = 0.1
  else
    # 5 seconds by default, but respect the provide values if any.
    attempts ||= 50
    backoff ||= 0.1
  end

  start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # It's common for tests to want to run simple tasks in a background thread
  # but call this method without the thread having even time to start.
  #
  # We add an extra attempt, interleaved by `Thread.pass`, in order to allow for
  # those simple cases to quickly succeed without a timed `sleep` call. This will
  # save simple test one `backoff` seconds sleep cycle.
  #
  # The total configured timeout is not reduced.
  (attempts + 1).times do |i|
    result = yield(attempts)
    return result if result

    if i == 0
      Thread.pass
    else
      sleep(backoff)
    end
  end

  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
  actual = "#{"%.2f" % elapsed} seconds, #{attempts} attempts with backoff #{backoff}"

  raise("Wait time exhausted! Requested: #{spec}, waited: #{actual}")
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
