# frozen_string_literal: true

# Backward compatibility shim for the old ruby_llm integration API.
# This file now just delegates to the new API.

module Braintrust
  module Trace
    module Contrib
      module Github
        module Crmne
          module RubyLLM
            # Wrap RubyLLM to automatically create spans for chat requests.
            # This is the legacy API - delegates to the new contrib framework.
            #
            # @param chat [RubyLLM::Chat, nil] the chat instance to wrap (if nil, wraps the class)
            # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
            # @return [RubyLLM::Chat, nil] the wrapped chat instance
            def self.wrap(chat = nil, tracer_provider: nil)
              Log.warn("Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap() is deprecated and will be removed in a future version: use Braintrust.instrument!() instead.")
              Braintrust.instrument!(:ruby_llm, target: chat, tracer_provider: tracer_provider)
              chat
            end

            # Unwrap RubyLLM to disable Braintrust tracing.
            # This is the legacy API - uses the Context pattern to disable tracing.
            #
            # Note: Prepended modules cannot be truly removed in Ruby.
            # This method sets `enabled: false` in the Context, which the
            # instrumentation checks before creating spans.
            #
            # @param chat [RubyLLM::Chat, nil] the chat instance to unwrap (if nil, unwraps the class)
            # @return [RubyLLM::Chat, nil] the chat instance
            def self.unwrap(chat = nil)
              Log.warn("Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.unwrap() is deprecated and will be removed in a future version.")

              target = chat || ::RubyLLM::Chat
              Braintrust::Contrib::Context.set!(target, enabled: false)
              chat
            end
          end
        end
      end
    end
  end
end
