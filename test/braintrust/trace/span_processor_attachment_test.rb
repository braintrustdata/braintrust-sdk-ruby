# frozen_string_literal: true

require "test_helper"
require "json"
require "braintrust/trace/attachment_processor/processor"
require "braintrust/trace/attachment_processor/uploader"

module Braintrust
  module Trace
    # End-to-end coverage of attachment processing through the SpanProcessor
    # using the in-memory OTel test rig.
    class SpanProcessorAttachmentTest < Minitest::Test
      include ::Test::Support::TracingHelper

      BASE64_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

      # Builds a rig whose Braintrust SpanProcessor has an attachment processor
      # backed by the given uploader.
      def build_rig(uploader)
        require "opentelemetry/sdk"
        exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
        tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
        state = get_unit_test_state
        simple = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
        processor = AttachmentProcessor::Processor.new(uploader: uploader)
        bt = SpanProcessor.new(simple, state, [], attachment_processor: processor)
        tracer_provider.add_span_processor(bt)
        [tracer_provider, exporter]
      end

      def emit_span(tracer_provider, input:)
        tracer = tracer_provider.tracer("test")
        span = tracer.start_span("Chat Completion")
        span.set_attribute("braintrust.input_json", input)
        span.finish
        tracer_provider.force_flush
      end

      def openai_input
        JSON.generate([{"role" => "user", "content" => [
          {"type" => "image_url", "image_url" => {"url" => "data:image/png;base64,#{BASE64_PNG}"}}
        ]}])
      end

      def test_replaces_attachment_in_exported_span
        uploader = AttachmentProcessor::NoopUploader.new
        tracer_provider, exporter = build_rig(uploader)

        emit_span(tracer_provider, input: openai_input)

        span = exporter.finished_spans.first
        refute_nil span
        parsed = JSON.parse(span.attributes["braintrust.input_json"])
        ref = parsed[0]["content"][0]["image_url"]["url"]
        assert_equal "braintrust_attachment", ref["type"]
        assert_equal "image/png", ref["content_type"]
      end

      def test_passes_through_span_without_attachments
        uploader = AttachmentProcessor::NoopUploader.new
        tracer_provider, exporter = build_rig(uploader)

        plain = JSON.generate([{"role" => "user", "content" => "hello"}])
        emit_span(tracer_provider, input: plain)

        span = exporter.finished_spans.first
        assert_equal plain, span.attributes["braintrust.input_json"]
      end

      def test_falls_back_to_inline_when_uploader_rejects
        # A rejecting uploader means the span must be exported with inline base64.
        rejecting = Class.new(AttachmentProcessor::NoopUploader) do
          def enqueue(_ref, _data) = false
        end.new
        tracer_provider, exporter = build_rig(rejecting)

        emit_span(tracer_provider, input: openai_input)

        span = exporter.finished_spans.first
        assert_equal openai_input, span.attributes["braintrust.input_json"],
          "rejected upload should leave inline base64 untouched"
      end
    end
  end
end
