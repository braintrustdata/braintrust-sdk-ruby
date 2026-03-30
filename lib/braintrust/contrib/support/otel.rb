# frozen_string_literal: true

require "json"

module Braintrust
  module Contrib
    module Support
      # OpenTelemetry utilities shared across all integrations.
      module OTel
        METADATA_CONTEXT_KEY = "braintrust.metadata"

        # Helper to safely set a JSON attribute on a span
        # Only sets the attribute if obj is present.
        # When setting "braintrust.metadata", automatically inherits metadata from the
        # parent OTel Context so parent spans can propagate metadata to child LLM spans.
        # @param span [OpenTelemetry::Trace::Span] the span to set attribute on
        # @param attr_name [String] the attribute name (e.g., "braintrust.output_json")
        # @param obj [Object] the object to serialize to JSON
        # @return [void]
        def self.set_json_attr(span, attr_name, obj)
          return unless obj
          inherit_context_metadata!(obj) if attr_name == METADATA_CONTEXT_KEY
          span.set_attribute(attr_name, JSON.generate(obj))
        end

        # Inherit metadata from the parent OTel Context into a child span's metadata hash.
        # Parent metadata provides defaults; the child span's own metadata wins on key collisions.
        # This enables parent spans (e.g. task spans) to propagate metadata like prompt origin
        # to auto-instrumented LLM call spans.
        # @param metadata [Hash] the child span's metadata hash (mutated in place)
        # @return [void]
        def self.inherit_context_metadata!(metadata)
          return unless metadata.is_a?(Hash)

          parent_metadata = OpenTelemetry::Context.current.value(METADATA_CONTEXT_KEY)
          return unless parent_metadata.is_a?(Hash)

          merged = parent_metadata.merge(metadata) { |_key, parent_val, child_val|
            if parent_val.is_a?(Hash) && child_val.is_a?(Hash)
              parent_val.merge(child_val)
            else
              child_val
            end
          }
          metadata.replace(merged)
        end
      end
    end
  end
end
