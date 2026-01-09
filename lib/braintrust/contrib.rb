# frozen_string_literal: true

require_relative "contrib/registry"
require_relative "contrib/integration"
require_relative "contrib/patcher"
require_relative "contrib/context"

module Braintrust
  # Instrument a registered integration by name.
  # This is the main entry point for activating integrations.
  #
  # @param name [Symbol] The integration name (e.g., :openai, :anthropic)
  # @param options [Hash] Optional configuration
  # @option options [Object] :target Optional target instance to instrument specifically
  # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
  # @return [void]
  #
  # @example Instrument all OpenAI clients
  #   Braintrust.instrument!(:openai)
  #
  # @example Instrument specific OpenAI client instance
  #   client = OpenAI::Client.new
  #   Braintrust.instrument!(:openai, target: client, tracer_provider: my_provider)
  def self.instrument!(name, **options)
    Braintrust::Contrib.instrument!(name, **options)
  end

  # Contrib framework for auto-instrumentation integrations.
  # Provides a consistent interface for all integrations and enables
  # reliable auto-instrumentation in later milestones.
  module Contrib
    class << self
      # Get the global registry instance.
      # @return [Registry]
      def registry
        Registry.instance
      end

      # Initialize the contrib framework with optional configuration.
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider, nil] Optional tracer provider
      # @return [void]
      def init(tracer_provider: nil)
        @default_tracer_provider = tracer_provider
      end

      # Instrument a registered integration by name.
      # This is the main entry point for activating integrations.
      #
      # @param name [Symbol] The integration name (e.g., :openai, :anthropic)
      # @param options [Hash] Optional configuration
      # @option options [Object] :target Optional target instance to instrument specifically
      # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
      # @return [void]
      #
      # @example Instrument all OpenAI clients
      #   Braintrust::Contrib.instrument!(:openai)
      #
      # @example Instrument specific OpenAI client instance
      #   client = OpenAI::Client.new
      #   Braintrust::Contrib.instrument!(:openai, target: client, tracer_provider: my_provider)
      def instrument!(name, **options)
        if (integration = registry[name])
          integration.instrument!(**options)
        else
          Braintrust::Log.error("No integration for '#{name}' is defined!")
        end
      end

      # Get the default tracer provider, falling back to OpenTelemetry global.
      # @return [OpenTelemetry::Trace::TracerProvider]
      def default_tracer_provider
        @default_tracer_provider || ::OpenTelemetry.tracer_provider
      end

      # Get the context for a target object.
      # @param target [Object] The object to retrieve context from
      # @return [Context, nil] The context if found, nil otherwise
      def context_for(target)
        Context.from(target)
      end

      # Get the tracer provider for a target.
      # Checks target's context first, then falls back to contrib default.
      # @param target [Object] The object to look up tracer provider for
      # @return [OpenTelemetry::Trace::TracerProvider]
      def tracer_provider_for(target)
        context_for(target)&.[](:tracer_provider) || default_tracer_provider
      end

      # Get a tracer for a target, using its context's tracer_provider if available.
      # @param target [Object] The object to look up context from
      # @param name [String] Tracer name
      # @return [OpenTelemetry::Trace::Tracer]
      def tracer_for(target, name: "braintrust")
        tracer_provider_for(target).tracer(name)
      end
    end
  end
end

# Load integration stubs (eager load minimal metadata).
require_relative "contrib/openai/integration"
require_relative "contrib/ruby_openai/integration"

# Register integrations
Braintrust::Contrib::OpenAI::Integration.register!
Braintrust::Contrib::RubyOpenAI::Integration.register!
