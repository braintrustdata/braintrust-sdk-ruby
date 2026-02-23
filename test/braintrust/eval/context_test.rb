# frozen_string_literal: true

require "test_helper"
require "braintrust/eval/context"

module Braintrust
  module Eval
    class ContextTest < Minitest::Test
      def setup
        @experiment_id = "exp_123"
      end

      def test_initialize_stores_experiment_id
        context = Context.new(experiment_id: @experiment_id)

        assert_equal @experiment_id, context.experiment_id
      end

      def test_dispose_is_callable
        context = Context.new(experiment_id: @experiment_id)

        # Dispose should be callable without errors
        # (currently no-op but kept for future extensibility)
        context.dispose
      end

      def test_multiple_contexts_have_independent_instances
        context1 = Context.new(experiment_id: "exp_1")
        context2 = Context.new(experiment_id: "exp_2")

        # Each context has its own experiment_id
        assert_equal "exp_1", context1.experiment_id
        assert_equal "exp_2", context2.experiment_id
      end
    end
  end
end
