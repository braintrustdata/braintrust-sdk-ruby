# frozen_string_literal: true

# Backward compatibility shim for the old OpenAI integration API.
# All instrumentation logic has been moved to lib/braintrust/contrib/openai/
# This file now just delegates to the new API.

require_relative "../../contrib"

module Braintrust
  module Trace
    module OpenAI
      # Wrap an OpenAI::Client to automatically create spans for chat completions and responses.
      # This is the legacy API - delegates to the new contrib framework.
      #
      # @param client [OpenAI::Client] the OpenAI client to wrap
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
      # @return [OpenAI::Client] the wrapped client
      def self.wrap(client, tracer_provider: nil)
        Braintrust::Contrib.instrument!(:openai, target: client, tracer_provider: tracer_provider)
        client
      end
    end
  end
end
