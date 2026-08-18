# frozen_string_literal: true

require "json"
require_relative "../version"
require_relative "../internal/env"

module Braintrust
  module Trace
    # Span origin provenance decoration.
    #
    # This is a *behavior*, not a type. Prepend it onto any exporter whose
    # +export(span_data, timeout:)+ it can +super+ into, and every exported
    # SpanData gains a +braintrust.context_json+ attribute carrying span origin
    # (SDK name/version, instrumentation scope, environment).
    #
    # Because it only ever touches the SpanData copies handed to *this*
    # exporter, the enrichment is invisible to any other exporter sharing the
    # same tracer provider - there is no global patch and nothing leaks onto a
    # customer's other OTel traces.
    module SpanOrigin
      CONTEXT_JSON_ATTR_KEY = "braintrust.context_json"

      # Exporter behavior: enrich each SpanData with span origin before export.
      # @param span_data [Array<OpenTelemetry::SDK::Trace::SpanData>]
      # @return [Integer] export result from the wrapped exporter
      def export(span_data, timeout: nil)
        # Environment is process-global and stable; read it once per batch
        # rather than once per span. It is cheap (ENV reads only).
        environment = Internal::Env.detect_environment
        enriched = span_data.map { |sd| SpanOrigin.enrich(sd, environment: environment) }
        super(enriched, timeout: timeout)
      end

      # Enrich a single SpanData with span origin provenance.
      # Mutates the SpanData in place (replacing its frozen attributes hash with
      # a new frozen hash - it never mutates the shared hash) and returns it.
      # @param span_data [OpenTelemetry::SDK::Trace::SpanData]
      # @param environment [Hash, nil] process environment ({type:, name:}) or nil
      # @return [OpenTelemetry::SDK::Trace::SpanData]
      def self.enrich(span_data, environment:)
        attributes = span_data.attributes || {}
        enriched_attributes = attributes_with_origin(
          attributes,
          instrumentation_name: instrumentation_name(span_data),
          environment: environment
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
