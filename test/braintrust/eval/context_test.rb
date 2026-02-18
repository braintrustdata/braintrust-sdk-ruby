# frozen_string_literal: true

require "test_helper"
require "braintrust/eval/context"

module Braintrust
  module Eval
    class ContextTest < Minitest::Test
      def setup
        @experiment_id = "exp_123"
      end

      def test_initialize_creates_span_cache
        context = Context.new(experiment_id: @experiment_id)

        assert_equal @experiment_id, context.experiment_id
        assert_instance_of SpanCache, context.span_cache
      end

      def test_initialize_with_custom_ttl_and_max_entries
        context = Context.new(
          experiment_id: @experiment_id,
          ttl: 600,
          max_entries: 500
        )

        assert_equal @experiment_id, context.experiment_id
        assert_instance_of SpanCache, context.span_cache
      end

      def test_dispose_clears_span_cache
        require_relative "../../../lib/braintrust/trace/span_registry"

        context = Context.new(experiment_id: @experiment_id)

        # Register to enable thread-local mode
        Trace::SpanRegistry.register(context.span_cache)

        # Write some data to cache (using thread-local storage)
        context.span_cache.write("root_1", "span_1", {input: "test"})

        # Verify data exists
        assert context.span_cache.get("root_1")

        # Dispose should clear the cache
        context.dispose

        # Cache should be empty
        assert_nil context.span_cache.get("root_1")
      ensure
        Trace::SpanRegistry.unregister
      end

      def test_multiple_contexts_have_independent_instances
        context1 = Context.new(experiment_id: "exp_1")
        context2 = Context.new(experiment_id: "exp_2")

        # Each context has its own SpanCache instance
        refute_equal context1.span_cache.object_id, context2.span_cache.object_id

        # Each context has its own experiment_id
        assert_equal "exp_1", context1.experiment_id
        assert_equal "exp_2", context2.experiment_id
      end

      def test_context_lifecycle_in_thread
        require_relative "../../../lib/braintrust/trace/span_registry"

        context = Context.new(experiment_id: @experiment_id)

        # Register and use context
        Trace::SpanRegistry.register(context.span_cache)
        context.span_cache.write("root_1", "span_1", {input: "test"})

        # Verify data exists
        assert context.span_cache.get("root_1")

        # Unregister and dispose
        Trace::SpanRegistry.unregister
        context.dispose

        # Data should be cleared
        Trace::SpanRegistry.register(context.span_cache)
        assert_nil context.span_cache.get("root_1")
      ensure
        Trace::SpanRegistry.unregister
      end
    end
  end
end
