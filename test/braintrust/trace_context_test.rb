# frozen_string_literal: true

require "test_helper"
require "braintrust/trace_context"
require "braintrust/state"
require "braintrust/span_cache"
require "braintrust/trace/span_registry"

module Braintrust
  class TraceContextTest < Minitest::Test
    def setup
      @state = State.new(
        api_key: "test-key",
        org_id: "test-org",
        api_url: "https://api.braintrust.dev",
        enable_tracing: false
      )

      @span_cache = SpanCache.new
      Trace::SpanRegistry.register(@span_cache)

      @trace_context = TraceContext.new(
        object_type: "experiment",
        object_id: "exp-123",
        root_span_id: "root-abc",
        span_cache: @span_cache,
        state: @state
      )
    end

    def teardown
      Trace::SpanRegistry.unregister
      Thread.current[:braintrust_span_cache_data] = nil
    end

    def test_configuration_returns_correct_hash
      config = @trace_context.configuration
      assert_equal "experiment", config[:object_type]
      assert_equal "exp-123", config[:object_id]
      assert_equal "root-abc", config[:root_span_id]
    end

    def test_get_spans_returns_cached_spans
      @span_cache.write("root-abc", "span1", {
        input: {messages: [{role: "user", content: "Hello"}]},
        output: {choices: [{message: {role: "assistant", content: "Hi"}}]},
        span_attributes: {type: "llm"}
      })

      spans = @trace_context.get_spans
      assert_equal 1, spans.size
      assert_equal "llm", spans.first.dig(:span_attributes, :type)
    end

    def test_get_spans_filters_by_single_type
      @span_cache.write("root-abc", "span1", {
        span_attributes: {type: "llm"}
      })
      @span_cache.write("root-abc", "span2", {
        span_attributes: {type: "score"}
      })

      llm_spans = @trace_context.get_spans(span_type: "llm")
      assert_equal 1, llm_spans.size
      assert_equal "llm", llm_spans.first.dig(:span_attributes, :type)
    end

    def test_get_spans_filters_by_multiple_types
      @span_cache.write("root-abc", "span1", {
        span_attributes: {type: "llm"}
      })
      @span_cache.write("root-abc", "span2", {
        span_attributes: {type: "score"}
      })
      @span_cache.write("root-abc", "span3", {
        span_attributes: {type: "task"}
      })

      spans = @trace_context.get_spans(span_type: ["llm", "score"])
      assert_equal 2, spans.size
      types = spans.map { |s| s.dig(:span_attributes, :type) }
      assert_includes types, "llm"
      assert_includes types, "score"
    end

    def test_get_spans_excludes_scorer_spans
      @span_cache.write("root-abc", "span1", {
        span_attributes: {type: "llm"}
      })
      @span_cache.write("root-abc", "span2", {
        span_attributes: {type: "score", purpose: "scorer"}
      })

      spans = @trace_context.get_spans
      assert_equal 1, spans.size
      assert_equal "llm", spans.first.dig(:span_attributes, :type)
    end

    def test_get_thread_reconstructs_message_thread
      @span_cache.write("root-abc", "span1", {
        input: {messages: [{role: "user", content: "Hello"}]},
        output: {choices: [{message: {role: "assistant", content: "Hi"}}]},
        span_attributes: {type: "llm"}
      })
      @span_cache.write("root-abc", "span2", {
        input: {messages: [{role: "user", content: "How are you?"}]},
        output: {choices: [{message: {role: "assistant", content: "Good"}}]},
        span_attributes: {type: "llm"}
      })

      thread = @trace_context.get_thread
      assert_equal 4, thread.size
      assert_equal "user", thread[0][:role]
      assert_equal "Hello", thread[0][:content]
      assert_equal "assistant", thread[1][:role]
      assert_equal "Hi", thread[1][:content]
    end

    def test_get_thread_deduplicates_input_messages
      msg1 = {role: "user", content: "Hello"}
      msg2 = {role: "user", content: "Hello"}

      @span_cache.write("root-abc", "span1", {
        input: {messages: [msg1]},
        output: {choices: [{message: {role: "assistant", content: "Hi"}}]},
        span_attributes: {type: "llm"}
      })
      @span_cache.write("root-abc", "span2", {
        input: {messages: [msg2]},
        output: {choices: [{message: {role: "assistant", content: "Hello again"}}]},
        span_attributes: {type: "llm"}
      })

      thread = @trace_context.get_thread
      assert_equal 3, thread.size
      user_messages = thread.select { |m| m[:role] == "user" }
      assert_equal 1, user_messages.size
    end

    def test_get_thread_always_includes_output_messages
      @span_cache.write("root-abc", "span1", {
        input: {messages: [{role: "user", content: "Hello"}]},
        output: {choices: [{message: {role: "assistant", content: "Hi"}}]},
        span_attributes: {type: "llm"}
      })
      @span_cache.write("root-abc", "span2", {
        input: {messages: [{role: "user", content: "Hello"}]},
        output: {choices: [{message: {role: "assistant", content: "Hi"}}]},
        span_attributes: {type: "llm"}
      })

      thread = @trace_context.get_thread
      assistant_messages = thread.select { |m| m[:role] == "assistant" }
      assert_equal 2, assistant_messages.size
    end

    def test_get_thread_handles_missing_input
      @span_cache.write("root-abc", "span1", {
        output: {choices: [{message: {role: "assistant", content: "Hi"}}]},
        span_attributes: {type: "llm"}
      })

      thread = @trace_context.get_thread
      assert_equal 1, thread.size
      assert_equal "assistant", thread[0][:role]
    end

    def test_get_thread_handles_missing_output
      @span_cache.write("root-abc", "span1", {
        input: {messages: [{role: "user", content: "Hello"}]},
        span_attributes: {type: "llm"}
      })

      thread = @trace_context.get_thread
      assert_equal 1, thread.size
      assert_equal "user", thread[0][:role]
    end

    def test_get_spans_returns_empty_when_cache_empty
      VCR.use_cassette("trace_context/get_spans_empty_btql") do
        # Cache is empty (no spans written)
        spans = @trace_context.get_spans
        # Should fall back to BTQL and return empty
        assert_equal [], spans
      end
    end
  end
end
