# frozen_string_literal: true

# BTX: cross-language LLM-span spec tests for the Braintrust Ruby SDK.
#
# Modes (controlled by the VCR_MODE / VCR_OFF env vars used by the rest of the suite):
#
#   replay (default): provider HTTP replayed from cassettes; spans captured
#     in-memory and converted to brainstore format for validation. No API keys
#     or network access required.
#
#   record (VCR_MODE=all|new_episodes): real provider API calls recorded to
#     cassettes; spans still validated in-memory.
#
#   live (VCR_OFF=true): real provider API calls; spans flushed to Braintrust
#     and fetched back via BTQL for validation.

require_relative "../test_helper"

require_relative "spec_fetcher"
require_relative "spec_loader"
require_relative "span_converter"
require_relative "span_validator"
require_relative "span_fetcher"
require_relative "cross_check"
require_relative "spec_executor"

module Braintrust
  module BTX
    module_function

    def live_mode?
      ENV["VCR_OFF"] == "true"
    end

    def cassette_name(spec)
      "btx/#{spec.provider}/#{spec.name}"
    end

    # Load every spec in the pinned ref. Specs the SDK cannot instrument are not
    # filtered out here — they are defined as tests and skipped at run time with
    # a clear reason, so they remain visible in the test output.
    def load_all_specs
      root = SpecFetcher.spec_root
      SpecLoader.load_specs(root)
    end
  end
end

class BtxTest < Minitest::Test
  include ::Test::Support::ProviderHelper

  # Build one test method per spec so failures are isolated and filterable.
  Braintrust::BTX.load_all_specs.each do |spec|
    test_name = "test_#{spec.provider}_#{spec.name}"
    define_method(test_name) do
      run_spec(spec)
    end
  end

  private

  def run_spec(spec)
    unless Braintrust::BTX::SpecExecutor.supported?(spec)
      skip "#{spec.display_name}: SDK has no instrumentation for " \
        "provider=#{spec.provider} endpoint=#{spec.endpoint}"
    end

    skip_unless_provider_available!(spec.provider)

    state = build_state
    live = Braintrust::BTX.live_mode?
    executor = Braintrust::BTX::SpecExecutor.new(state, live: live)

    result = with_cassette(spec) { executor.execute(spec) }

    # The in-memory OTel spans are converted to brainstore format in every mode.
    converted = Braintrust::BTX::SpanConverter.to_brainstore_spans(result.otel_spans)

    if live
      run_spec_live(spec, result, state, converted)
    else
      refute_empty converted, "#{spec.display_name}: no spans captured"
      Braintrust::BTX::SpanValidator.validate_spans(converted, spec)
    end
  end

  # Live mode validates three ways so a passing live run also guarantees the
  # in-memory path is correct:
  #   1. the converted in-memory spans satisfy the spec,
  #   2. the live brainstore spans (via BTQL) satisfy the spec,
  #   3. the converted spans match the live spans (lenient subset cross-check).
  def run_spec_live(spec, result, state, converted)
    refute_empty converted, "#{spec.display_name}: no in-memory spans captured"

    # 1. In-memory spans must independently pass the spec.
    begin
      Braintrust::BTX::SpanValidator.validate_spans(converted, spec)
    rescue Braintrust::BTX::ValidationError => e
      flunk "#{spec.display_name}: in-memory spans failed spec validation in live mode " \
        "(the converter/instrumentation diverged from the spec):\n#{e.message}"
    end

    # 2. Authoritative live spans must pass the spec.
    live_spans = fetch_live_spans(spec, result, state)
    refute_empty live_spans, "#{spec.display_name}: no live spans fetched"
    Braintrust::BTX::SpanValidator.validate_spans(live_spans, spec)

    # 3. In-memory conversion must be consistent with what the backend stored.
    Braintrust::BTX::CrossCheck.assert_matches(converted, live_spans, spec.display_name)
  end

  def with_cassette(spec)
    return yield if Braintrust::BTX.live_mode?

    VCR.use_cassette(Braintrust::BTX.cassette_name(spec), match_requests_on: [:method, :uri, :body]) do
      yield
    end
  end

  def fetch_live_spans(spec, result, state)
    fetcher = Braintrust::BTX::SpanFetcher.new(api_url: state.api_url, api_key: state.api_key)
    project_id = Braintrust::BTX::SpanFetcher.project_id_for(project_name, api_url: state.api_url, api_key: state.api_key)
    fetcher.fetch(result.root_span_id, project_id, spec.expected_brainstore_spans.length)
  end

  # The Braintrust project BTX logs to (and reads back from) in live mode.
  PROJECT_NAME = "ruby-unit-test"

  def project_name
    PROJECT_NAME
  end

  def build_state
    if Braintrust::BTX.live_mode?
      Braintrust.init(
        api_key: get_braintrust_key,
        set_global: false,
        blocking_login: true,
        default_project: project_name
      )
    else
      get_unit_test_state(default_project: project_name)
    end
  end

  def skip_unless_provider_available!(provider)
    case provider
    when "openai"
      if Gem.loaded_specs["ruby-openai"]
        skip "official openai gem not available (found ruby-openai)"
      end
      skip "openai gem not available" unless Gem.loaded_specs["openai"]
    when "anthropic"
      skip "anthropic gem not available" unless Gem.loaded_specs["anthropic"]
    end
  end
end
