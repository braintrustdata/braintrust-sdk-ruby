# frozen_string_literal: true

# Backward compatibility shim for the old ruby-openai integration API.
# This file now just delegates to the new API.

module Braintrust
  module Trace
    module AlexRudall
      module RubyOpenAI
        # Wrap an OpenAI::Client (ruby-openai gem) to automatically create spans.
        # This is the legacy API - delegates to the new contrib framework.
        #
        # @param client [OpenAI::Client] the OpenAI client to wrap
        # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
        # @return [OpenAI::Client] the wrapped client
        def self.wrap(client, tracer_provider: nil)
          Log.warn("Braintrust::Trace::AlexRudall::RubyOpenAI.wrap() is deprecated and will be removed in a future version: use Braintrust.instrument!() instead.")
          Braintrust.instrument!(:ruby_openai, target: client, tracer_provider: tracer_provider)
          client
        end
      end
    end
  end
end
