# frozen_string_literal: true

require "opentelemetry/sdk"

module Braintrust
  module Trace
    # Custom span processor that adds Braintrust-specific attributes to spans
    class SpanProcessor
      PARENT_ATTR_KEY = "braintrust.parent"
      ORG_ATTR_KEY = "braintrust.org"
      APP_URL_ATTR_KEY = "braintrust.app_url"

      def initialize(wrapped_processor, state)
        @wrapped = wrapped_processor
        @state = state
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

      # Called when a span ends
      def on_finish(span)
        @wrapped.on_finish(span)
      end

      # Shutdown the processor
      def shutdown(timeout: nil)
        @wrapped.shutdown(timeout: timeout)
      end

      # Force flush any buffered spans
      def force_flush(timeout: nil)
        @wrapped.force_flush(timeout: timeout)
      end

      private

      def default_parent
        @state.default_parent || "project_name:ruby-sdk-default-project"
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
    end
  end
end
