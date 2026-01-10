# frozen_string_literal: true

require "json"

module Braintrust
  module Contrib
    module Support
      # OpenTelemetry utilities shared across all integrations.
      module OTel
        # Helper to safely set a JSON attribute on a span
        # Only sets the attribute if obj is present
        # @param span [OpenTelemetry::Trace::Span] the span to set attribute on
        # @param attr_name [String] the attribute name (e.g., "braintrust.output_json")
        # @param obj [Object] the object to serialize to JSON
        # @return [void]
        def self.set_json_attr(span, attr_name, obj)
          return unless obj
          span.set_attribute(attr_name, JSON.generate(obj))
        end
      end
    end
  end
end
