# frozen_string_literal: true

# Backward compatibility shim for the old Anthropic integration API.
# This file now just delegates to the new API.

require_relative "../../../braintrust"

module Braintrust
  module Trace
    module Anthropic
      # Wrap an Anthropic::Client to automatically create spans for messages.
      # This is the legacy API - delegates to the new contrib framework.
      #
      # @param client [Anthropic::Client] the Anthropic client to wrap
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
      # @return [Anthropic::Client] the wrapped client
      def self.wrap(client, tracer_provider: nil)
        Log.warn("Braintrust::Trace::Anthropic.wrap() is deprecated and will be removed in a future version: use Braintrust.instrument!() instead.")
        Braintrust.instrument!(:anthropic, target: client, tracer_provider: tracer_provider)
        client
      end
    end
  end
end
