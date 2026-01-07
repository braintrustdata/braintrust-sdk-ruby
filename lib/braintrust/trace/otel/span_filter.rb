# frozen_string_literal: true

module Braintrust
  module Trace
    module OTel
      # Span filtering logic for Braintrust tracing
      #
      # Filters allow you to control which spans are exported to Braintrust.
      # This is useful for reducing noise and cost by filtering out non-AI spans.
      #
      # Filter functions take a span and return:
      #   1 = keep the span
      #   0 = no influence (continue to next filter)
      #  -1 = drop the span
      module SpanFilter
        # System attributes that should be ignored when checking for AI indicators
        SYSTEM_ATTRIBUTES = [
          "braintrust.parent",
          "braintrust.org",
          "braintrust.app_url"
        ].freeze

        # Prefixes that indicate an AI-related span
        AI_PREFIXES = [
          "gen_ai.",
          "braintrust.",
          "llm.",
          "ai.",
          "traceloop."
        ].freeze

        # AI span filter that keeps spans with AI-related names or attributes
        #
        # @param span [OpenTelemetry::SDK::Trace::SpanData] The span to filter
        # @return [Integer] 1 to keep, -1 to drop, 0 for no influence
        def self.ai_filter(span)
          # Check span name for AI prefixes
          span_name = span.name
          AI_PREFIXES.each do |prefix|
            return 1 if span_name.start_with?(prefix)
          end

          # Check attributes for AI prefixes (skip system attributes)
          # span.attributes returns a hash
          attributes = span.attributes || {}
          attributes.each do |attr_key, _attr_value|
            attr_key_str = attr_key.to_s
            next if SYSTEM_ATTRIBUTES.include?(attr_key_str)

            AI_PREFIXES.each do |prefix|
              return 1 if attr_key_str.start_with?(prefix)
            end
          end

          # Drop non-AI spans
          -1
        end
      end
    end
  end
end
