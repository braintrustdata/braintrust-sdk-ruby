# frozen_string_literal: true

require "json"
require_relative "../version"

module Braintrust
  module Trace
    module SpanOrigin
      CONTEXT_JSON_ATTR_KEY = "braintrust.context_json"
      ENVIRONMENT_IVAR = :@braintrust_span_origin_environment

      def self.install!
        span_class = OpenTelemetry::SDK::Trace::Span
        span_class.prepend(self) unless span_class < self
      end

      def to_span_data
        span_data = super
        attributes = span_data.attributes || {}
        enriched_attributes = SpanOrigin.attributes_with_origin(
          attributes,
          instrumentation_name: SpanOrigin.instrumentation_name(self),
          environment: instance_variable_get(ENVIRONMENT_IVAR)
        )

        return span_data if enriched_attributes.equal?(attributes)

        span_data.attributes = enriched_attributes.freeze
        span_data.total_recorded_attributes = enriched_attributes.length
        span_data
      end

      def self.attributes_with_origin(attributes, instrumentation_name:, environment:)
        context = parse_context_json(attributes[CONTEXT_JSON_ATTR_KEY])
        span_origin = context["span_origin"].is_a?(Hash) ? context["span_origin"] : {}

        span_origin_changed = false
        unless span_origin.key?("name")
          span_origin["name"] = "braintrust.sdk.ruby"
          span_origin_changed = true
        end
        unless span_origin.key?("version")
          span_origin["version"] = Braintrust::VERSION
          span_origin_changed = true
        end
        unless span_origin.key?("instrumentation")
          span_origin["instrumentation"] = {"name" => instrumentation_name}
          span_origin_changed = true
        end
        if environment && !span_origin.key?("environment")
          span_origin["environment"] = environment
          span_origin_changed = true
        end

        context_changed = context["span_origin"] != span_origin || span_origin_changed
        return attributes unless context_changed

        context["span_origin"] = span_origin
        attributes.merge(CONTEXT_JSON_ATTR_KEY => JSON.generate(context))
      end

      def self.parse_context_json(raw)
        return {} unless raw.is_a?(String) && !raw.strip.empty?

        parsed = JSON.parse(raw)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def self.instrumentation_name(span)
        if span.respond_to?(:instrumentation_scope) && span.instrumentation_scope&.respond_to?(:name)
          return span.instrumentation_scope.name
        end
        if span.respond_to?(:instrumentation_library) && span.instrumentation_library&.respond_to?(:name)
          return span.instrumentation_library.name
        end

        "braintrust-ruby"
      end
    end
  end
end
