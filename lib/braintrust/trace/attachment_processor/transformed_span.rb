# frozen_string_literal: true

module Braintrust
  module Trace
    module AttachmentProcessor
      # Wraps an ended OTel span and overrides selected attributes.
      #
      # By the time a span reaches +SpanProcessor#on_finish+ it has already
      # ended and its attributes are frozen, so they cannot be mutated in place.
      # The downstream processors (Simple/Batch) export by calling
      # +span.to_span_data+, so this wrapper overrides +to_span_data+ to return a
      # +SpanData+ whose attributes carry the replacements. Every other method is
      # delegated to the original span.
      #
      # This is the Ruby equivalent of the Go SDK's transformedSpan and Java's
      # TransformedReadableSpan.
      class TransformedSpan
        # @param span the original ended span (responds to +to_span_data+)
        # @param overrides [Hash{String=>String}] attribute key => new value
        def initialize(span, overrides)
          @span = span
          @overrides = overrides
        end

        # @return [OpenTelemetry::SDK::Trace::SpanData] span data with overridden attributes
        def to_span_data
          data = @span.to_span_data
          attrs = (data.attributes || {}).merge(@overrides)
          # SpanData is a Struct; copy it with the :attributes member replaced.
          # Look the member up by name so we are robust to field ordering
          # changes across OTel SDK versions.
          idx = data.members.index(:attributes)
          values = data.to_a
          values[idx] = attrs
          data.class.new(*values)
        end

        def respond_to_missing?(name, include_private = false)
          @span.respond_to?(name, include_private) || super
        end

        def method_missing(name, *args, **kwargs, &block)
          if @span.respond_to?(name)
            @span.send(name, *args, **kwargs, &block)
          else
            super
          end
        end
      end
    end
  end
end
