# frozen_string_literal: true

require "test_helper"
require "opentelemetry/sdk"
require "braintrust/trace/attachment_processor/transformed_span"

module Braintrust
  module Trace
    module AttachmentProcessor
      class TransformedSpanTest < Minitest::Test
        include ::Test::Support::TracingHelper

        def make_span
          rig = setup_otel_test_rig
          tracer = rig.tracer
          span = tracer.start_span("test")
          span.set_attribute("braintrust.input_json", %([{"role":"user"}]))
          span.set_attribute("keep", "original")
          span.finish
          span
        end

        def test_overrides_attribute_in_span_data
          span = make_span
          wrapped = TransformedSpan.new(span, {"braintrust.input_json" => "REPLACED"})
          data = wrapped.to_span_data

          assert_equal "REPLACED", data.attributes["braintrust.input_json"]
          assert_equal "original", data.attributes["keep"], "non-overridden attributes preserved"
        end

        def test_does_not_mutate_original_span
          span = make_span
          TransformedSpan.new(span, {"braintrust.input_json" => "REPLACED"}).to_span_data

          assert_equal %([{"role":"user"}]), span.to_span_data.attributes["braintrust.input_json"]
        end

        def test_delegates_other_methods
          span = make_span
          wrapped = TransformedSpan.new(span, {})
          assert_equal span.to_span_data.name, wrapped.to_span_data.name
          assert wrapped.respond_to?(:to_span_data)
        end

        def test_preserves_other_span_data_fields
          span = make_span
          original = span.to_span_data
          data = TransformedSpan.new(span, {"keep" => "changed"}).to_span_data

          assert_equal original.name, data.name
          assert_equal original.trace_id, data.trace_id
          assert_equal original.span_id, data.span_id
          assert_equal original.kind, data.kind
        end
      end
    end
  end
end
