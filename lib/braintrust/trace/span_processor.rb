# frozen_string_literal: true

require "opentelemetry/sdk"
require_relative "attachment_processor/transformed_span"

module Braintrust
  module Trace
    # Custom span processor that adds Braintrust-specific attributes to spans,
    # optionally filters spans based on custom filter functions, and (when
    # enabled) replaces inline base64 attachments with uploaded references.
    class SpanProcessor
      PARENT_ATTR_KEY = "braintrust.parent"
      ORG_ATTR_KEY = "braintrust.org"
      APP_URL_ATTR_KEY = "braintrust.app_url"
      INPUT_JSON_ATTR_KEY = "braintrust.input_json"
      OUTPUT_JSON_ATTR_KEY = "braintrust.output_json"

      # Default time budget for draining/shutting down the uploader when the
      # caller does not provide one.
      DEFAULT_FLUSH_TIMEOUT = 30.0

      # @param wrapped_processor the delegate span processor (Simple/Batch)
      # @param state [State]
      # @param filters [Array<Proc>]
      # @param attachment_processor [AttachmentProcessor::Processor, nil] when
      #   present, scans/rewrites attachment data in onEnd
      def initialize(wrapped_processor, state, filters = [], attachment_processor: nil)
        @wrapped = wrapped_processor
        @state = state
        @filters = filters || []
        @attachment_processor = attachment_processor
      end

      def on_start(span, parent_context)
        # Add default parent if span doesn't already have one
        has_parent = span.respond_to?(:attributes) && span.attributes&.key?(PARENT_ATTR_KEY)

        unless has_parent
          # Try to inherit parent from parent span in context
          parent_value = get_parent_from_context(parent_context) || default_parent
          span.set_attribute(PARENT_ATTR_KEY, parent_value)
        end

        # Always add org and app_url
        span.set_attribute(ORG_ATTR_KEY, @state.org_name) if @state.org_name
        span.set_attribute(APP_URL_ATTR_KEY, @state.app_url) if @state.app_url

        # Delegate to wrapped processor
        @wrapped.on_start(span, parent_context)
      end

      # Called when a span ends - apply filters, process attachments, then forward.
      def on_finish(span)
        return unless should_forward_span?(span)

        span = process_attachments(span) if @attachment_processor
        @wrapped.on_finish(span)
      end

      # Shutdown the processor.
      #
      # The wrapped exporter is flushed/shut down first so that spans carrying
      # attachment references reach the collector, then the uploader is drained
      # so the referenced binary data is available in object storage.
      def shutdown(timeout: nil)
        result = @wrapped.shutdown(timeout: timeout)
        shutdown_uploader(timeout)
        result
      end

      # Force flush any buffered spans, then drain the uploader.
      def force_flush(timeout: nil)
        result = @wrapped.force_flush(timeout: timeout)
        @attachment_processor&.uploader&.force_flush(timeout || DEFAULT_FLUSH_TIMEOUT)
        result
      end

      private

      # Scan input/output JSON attributes for base64 attachments. If either was
      # rewritten, forward a transformed span carrying the new values; otherwise
      # forward the original span unchanged.
      def process_attachments(span)
        attrs = span.respond_to?(:attributes) ? span.attributes : nil
        return span unless attrs

        input_json = attrs[INPUT_JSON_ATTR_KEY]
        output_json = attrs[OUTPUT_JSON_ATTR_KEY]

        new_input = @attachment_processor.process_and_upload(input_json)
        new_output = @attachment_processor.process_and_upload(output_json)

        overrides = {}
        overrides[INPUT_JSON_ATTR_KEY] = new_input unless new_input.equal?(input_json)
        overrides[OUTPUT_JSON_ATTR_KEY] = new_output unless new_output.equal?(output_json)
        return span if overrides.empty?

        AttachmentProcessor::TransformedSpan.new(span, overrides)
      rescue => e
        # Attachment processing must never prevent a span from being exported.
        Braintrust::Log.debug("Braintrust: attachment processing error: #{e.message}")
        span
      end

      # Drain/shut down the uploader, honoring the caller's deadline. If the
      # uploader cannot finish in time, abandon the wait rather than blocking
      # the caller past their budget (the worker keeps running in the
      # background until process exit).
      def shutdown_uploader(timeout)
        uploader = @attachment_processor&.uploader
        return unless uploader

        if timeout
          # Run shutdown in the background and wait up to the caller's deadline.
          # If it doesn't finish, abandon the wait and let the worker continue
          # draining in the background rather than blocking past the budget.
          thread = Thread.new { uploader.shutdown }
          unless thread.join(timeout)
            Braintrust::Log.debug("Braintrust: attachment uploader shutdown exceeded caller deadline; continuing in background")
          end
        else
          uploader.shutdown
        end
      end

      def default_parent
        # If default_project is set, format it as "project_name:value"
        # The default_project should be a plain project name (e.g., "my-project")
        # not a formatted parent string (e.g., "project_name:my-project")
        if @state.default_project
          "project_name:#{@state.default_project}"
        else
          "project_name:ruby-sdk-default-project"
        end
      end

      # Get parent attribute from parent span in context
      def get_parent_from_context(parent_context)
        return nil unless parent_context

        # Get the current span from the context (the parent span)
        parent_span = OpenTelemetry::Trace.current_span(parent_context)
        return nil unless parent_span
        return nil unless parent_span.respond_to?(:attributes)

        # Return the parent attribute from the parent span
        parent_span.attributes&.[](PARENT_ATTR_KEY)
      end

      # Determine if a span should be forwarded to the wrapped processor
      # based on configured filters
      def should_forward_span?(span)
        # If no filters, keep everything
        return true if @filters.empty?

        # Apply filters in order - first non-zero result wins
        @filters.each do |filter|
          result = filter.call(span)
          return true if result > 0  # Keep span
          return false if result < 0 # Drop span
          # result == 0: no influence, continue to next filter
        end

        # All filters returned 0 (no influence), default to keep
        true
      end
    end
  end
end
