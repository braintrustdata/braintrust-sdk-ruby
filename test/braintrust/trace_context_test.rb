# frozen_string_literal: true

require "test_helper"
require "braintrust/trace_context"
require "braintrust/state"

module Braintrust
  class TraceContextTest < Minitest::Test
    def setup
      @state = State.new(
        api_key: "test-key",
        org_id: "test-org",
        api_url: "https://api.braintrust.dev",
        enable_tracing: false
      )

      @trace_context = TraceContext.new(
        object_type: "experiment",
        object_id: "exp-123",
        root_span_id: "root-abc",
        state: @state
      )
    end

    def teardown
      Thread.current[:braintrust_span_cache_data] = nil
    end

    def test_configuration_returns_correct_hash
      config = @trace_context.configuration
      assert_equal "experiment", config[:object_type]
      assert_equal "exp-123", config[:object_id]
      assert_equal "root-abc", config[:root_span_id]
    end

    def test_get_spans_returns_empty_when_no_spans_exist
      VCR.use_cassette("trace_context/get_spans_empty_btql") do
        # BTQL query should return empty
        spans = @trace_context.get_spans
        assert_equal [], spans
      end
    end

    # TODO: Add more comprehensive tests with VCR cassettes for:
    # - test_get_spans_returns_btql_spans
    # - test_get_spans_filters_by_single_type
    # - test_get_spans_filters_by_multiple_types
    # - test_get_spans_excludes_scorer_spans
    # - test_get_spans_caches_btql_results
    # - test_get_thread_reconstructs_message_thread
    # - test_get_thread_deduplicates_input_messages
    # - test_get_thread_always_includes_output_messages
    # - test_get_thread_handles_missing_input
    # - test_get_thread_handles_missing_output
    #
    # These tests require proper VCR cassettes with BTQL responses containing spans
  end
end
