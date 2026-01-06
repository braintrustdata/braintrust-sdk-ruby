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

require_relative "support/assert_helper"
require_relative "support/braintrust_helper"
require_relative "support/provider_helper"
require_relative "support/tracing_helper"

# Include helper in all test cases
class Minitest::Test
  include ::Test::Support::AssertHelper
  include ::Test::Support::BraintrustHelper
  include ::Test::Support::ProviderHelper
  include ::Test::Support::TracingHelper

  # Use Minitest hooks to clear global state after every test
  # This ensures cleanup happens even if individual tests don't have teardown methods
  def after_teardown
    Braintrust::State.instance_variable_set(:@global_state, nil)
    super
  end
end
