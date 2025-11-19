# frozen_string_literal: true

require "opentelemetry/sdk"
require_relative "../logger"

module Braintrust
  module Trace
    # Custom span processor that adds Braintrust-specific attributes to spans
    # and optionally filters spans based on custom filter functions.
    class SpanProcessor
      PARENT_ATTR_KEY = "braintrust.parent"
      ORG_ATTR_KEY = "braintrust.org"
      APP_URL_ATTR_KEY = "braintrust.app_url"

      def initialize(wrapped_processor, state, filters = [])
        @wrapped = wrapped_processor
        @state = state
        @filters = filters || []

        Log.debug("SpanProcessor initialized with #{@filters.length} filter(s)")
        Log.debug("  Wrapped processor: #{@wrapped.class.name}")
        Log.debug("  Organization: #{@state.org_name}") if @state.org_name
        Log.debug("  Default project: #{@state.default_project}") if @state.default_project
      end

      def on_start(span, parent_context)
        span_id = span.context.hex_span_id rescue "unknown"
        span_name = span.name rescue "unknown"

        Log.debug("SpanProcessor.on_start: span=#{span_name} (#{span_id})")

        # Add default parent if span doesn't already have one
        has_parent = span.respond_to?(:attributes) && span.attributes&.key?(PARENT_ATTR_KEY)

        unless has_parent
          # Try to inherit parent from parent span in context
          parent_value = get_parent_from_context(parent_context) || default_parent
          span.set_attribute(PARENT_ATTR_KEY, parent_value)
          Log.debug("  Set #{PARENT_ATTR_KEY}=#{parent_value}")
        else
          existing_parent = span.attributes[PARENT_ATTR_KEY]
          Log.debug("  Span already has #{PARENT_ATTR_KEY}=#{existing_parent}")
        end

        # Always add org and app_url
        if @state.org_name
          span.set_attribute(ORG_ATTR_KEY, @state.org_name)
          Log.debug("  Set #{ORG_ATTR_KEY}=#{@state.org_name}")
        end

        if @state.app_url
          span.set_attribute(APP_URL_ATTR_KEY, @state.app_url)
          Log.debug("  Set #{APP_URL_ATTR_KEY}=#{@state.app_url}")
        end

        # Delegate to wrapped processor
        @wrapped.on_start(span, parent_context)
        Log.debug("  Delegated to wrapped processor")
      end

      # Called when a span ends - apply filters before forwarding
      def on_finish(span)
        span_id = span.context.hex_span_id rescue "unknown"
        span_name = span.name rescue "unknown"

        Log.debug("SpanProcessor.on_finish: span=#{span_name} (#{span_id})")

        # Only forward span if it passes filters
        if should_forward_span?(span)
          Log.debug("  Forwarding span to wrapped processor")
          @wrapped.on_finish(span)
        else
          Log.debug("  Span filtered out, not forwarding")
        end
      end

      # Shutdown the processor
      def shutdown(timeout: nil)
        Log.debug("SpanProcessor.shutdown called (timeout: #{timeout})")
        result = @wrapped.shutdown(timeout: timeout)
        Log.debug("SpanProcessor.shutdown completed")
        result
      end

      # Force flush any buffered spans
      def force_flush(timeout: nil)
        Log.debug("SpanProcessor.force_flush called (timeout: #{timeout})")
        result = @wrapped.force_flush(timeout: timeout)
        Log.debug("SpanProcessor.force_flush completed")
        result
      end

      private

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
        parent_value = parent_span.attributes&.[](PARENT_ATTR_KEY)
        if parent_value
          Log.debug("    Inherited parent from context: #{parent_value}")
        else
          Log.debug("    No parent found in context")
        end
        parent_value
      end

      # Determine if a span should be forwarded to the wrapped processor
      # based on configured filters
      def should_forward_span?(span)
        # Always keep root spans (spans with no parent)
        # Check if parent_span_id is the invalid/zero span ID
        is_root = span.parent_span_id == OpenTelemetry::Trace::INVALID_SPAN_ID
        if is_root
          Log.debug("    Span is root span, keeping")
          return true
        end

        # If no filters, keep everything
        if @filters.empty?
          Log.debug("    No filters configured, keeping span")
          return true
        end

        Log.debug("    Applying #{@filters.length} filter(s)")

        # Apply filters in order - first non-zero result wins
        @filters.each_with_index do |filter, index|
          result = filter.call(span)
          Log.debug("      Filter #{index + 1} returned: #{result}")

          if result > 0
            Log.debug("      Filter #{index + 1} says keep, stopping filter chain")
            return true
          elsif result < 0
            Log.debug("      Filter #{index + 1} says drop, stopping filter chain")
            return false
          end
          # result == 0: no influence, continue to next filter
        end

        # All filters returned 0 (no influence), default to keep
        Log.debug("    All filters returned 0 (no influence), defaulting to keep")
        true
      end
    end
  end
end
