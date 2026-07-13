# frozen_string_literal: true

require "json"
require "opentelemetry/sdk"
require_relative "../version"

module Braintrust
  module Trace
    # Custom span processor that adds Braintrust-specific attributes to spans
    # and optionally filters spans based on custom filter functions.
    class SpanProcessor
      PARENT_ATTR_KEY = "braintrust.parent"
      ORG_ATTR_KEY = "braintrust.org"
      APP_URL_ATTR_KEY = "braintrust.app_url"
      CONTEXT_JSON_ATTR_KEY = "braintrust.context_json"
      ENVIRONMENT_TYPE_ATTR_KEY = "braintrust.environment.type"
      ENVIRONMENT_NAME_ATTR_KEY = "braintrust.environment.name"

      def initialize(wrapped_processor, state, filters = [])
        @wrapped = wrapped_processor
        @state = state
        @filters = filters || []
      end

      def on_start(span, parent_context)
        add_span_origin(span)

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

      # Called when a span ends - apply filters before forwarding
      def on_finish(span)
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

      def add_span_origin(span)
        context = parse_context_json(span.respond_to?(:attributes) ? span.attributes&.[](CONTEXT_JSON_ATTR_KEY) : nil)
        span_origin = context["span_origin"].is_a?(Hash) ? context["span_origin"] : {}
        span_origin["name"] ||= "braintrust.sdk.ruby"
        span_origin["version"] ||= Braintrust::VERSION
        span_origin["instrumentation"] ||= {"name" => instrumentation_name(span)}
        if @state.config&.environment && !span_origin.key?("environment")
          environment = {"type" => @state.config.environment[:type]}
          environment["name"] = @state.config.environment[:name] if @state.config.environment[:name]
          span_origin["environment"] = environment
        end
        context["span_origin"] = span_origin
        span.set_attribute(CONTEXT_JSON_ATTR_KEY, JSON.generate(context))

        return unless @state.config&.environment

        span.set_attribute(ENVIRONMENT_TYPE_ATTR_KEY, @state.config.environment[:type])
        span.set_attribute(ENVIRONMENT_NAME_ATTR_KEY, @state.config.environment[:name]) if @state.config.environment[:name]
      end

      def parse_context_json(raw)
        return {} unless raw.is_a?(String) && !raw.strip.empty?

        parsed = JSON.parse(raw)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def instrumentation_name(span)
        return span.instrumentation_scope.name if span.respond_to?(:instrumentation_scope) && span.instrumentation_scope&.respond_to?(:name)
        return span.instrumentation_library.name if span.respond_to?(:instrumentation_library) && span.instrumentation_library&.respond_to?(:name)

        "braintrust-ruby"
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
