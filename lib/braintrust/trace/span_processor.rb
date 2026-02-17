# frozen_string_literal: true

require "opentelemetry/sdk"
require_relative "span_registry"

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

      # Called when a span ends - write to cache and apply filters before forwarding
      def on_finish(span)
        # Write to span cache (checks both registry and state-based cache)
        write_to_cache(span)

        # Only forward span if it passes filters
        @wrapped.on_finish(span) if should_forward_span?(span)
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

      # Write span data to cache for TraceContext access
      # Gets cache from SpanRegistry (must be registered during eval)
      # @param span [OpenTelemetry::SDK::Trace::Span, OpenTelemetry::SDK::Trace::SpanData] The span
      def write_to_cache(span)
        return unless span.respond_to?(:attributes)

        # Get cache from SpanRegistry (registered by Eval.run)
        cache = SpanRegistry.current

        # Skip if no cache registered (not in an eval context)
        return unless cache

        # Extract root_span_id from trace_id (hex-encoded)
        # For Span objects, use context; for SpanData, use the direct attributes
        if span.respond_to?(:context)
          root_span_id = span.context.trace_id.unpack1("H*")
          span_id = span.context.span_id.unpack1("H*")
        else
          root_span_id = span.trace_id.unpack1("H*")
          span_id = span.span_id.unpack1("H*")
        end

        # Extract Braintrust-specific attributes
        attrs = span.attributes || {}
        cached_data = {}

        # Parse JSON attributes
        if attrs["braintrust.input_json"]
          cached_data[:input] = begin
            JSON.parse(attrs["braintrust.input_json"], symbolize_names: true)
          rescue
            nil
          end
        end

        if attrs["braintrust.output_json"]
          cached_data[:output] = begin
            JSON.parse(attrs["braintrust.output_json"], symbolize_names: true)
          rescue
            nil
          end
        end

        if attrs["braintrust.metadata"]
          cached_data[:metadata] = begin
            JSON.parse(attrs["braintrust.metadata"], symbolize_names: true)
          rescue
            nil
          end
        end

        if attrs["braintrust.span_attributes"]
          cached_data[:span_attributes] = begin
            JSON.parse(attrs["braintrust.span_attributes"], symbolize_names: true)
          rescue
            nil
          end
        end

        # Add span_id and span_parents
        cached_data[:span_id] = span_id

        # Extract parent span IDs from the span
        if span.respond_to?(:parent_span_id) && span.parent_span_id
          if span.parent_span_id != OpenTelemetry::Trace::INVALID_SPAN_ID
            parent_span_id = span.parent_span_id.unpack1("H*")
          end
        end
        cached_data[:span_parents] = parent_span_id ? [parent_span_id] : []

        # Write to cache
        cache.write(root_span_id, span_id, cached_data)
      rescue => e
        # Silently ignore cache write errors
        require_relative "../logger"
        Log.debug("Failed to write span to cache: #{e.message}")
      end

      # Determine if a span should be forwarded to the wrapped processor
      # based on configured filters
      def should_forward_span?(span)
        # Always keep root spans (spans with no parent)
        # Check if parent_span_id is the invalid/zero span ID
        is_root = span.parent_span_id == OpenTelemetry::Trace::INVALID_SPAN_ID
        return true if is_root

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
