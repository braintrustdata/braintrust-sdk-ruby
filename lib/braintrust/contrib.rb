# frozen_string_literal: true

require_relative "contrib/registry"
require_relative "contrib/integration"
require_relative "contrib/patcher"
require_relative "contrib/context"

module Braintrust
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
      #
      # @param name [Symbol] The integration name (e.g., :openai, :anthropic)
      # @param options [Hash] Optional configuration
      # @option options [Object] :target Optional target instance to instrument specifically
      # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
      # @return [Boolean] true if instrumentation succeeded
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
          false
        end
      end

      # Auto-instrument available integrations.
      # Discovers which integrations have their target libraries loaded
      # and instruments them automatically.
      #
      # @param only [Array<Symbol>] whitelist - only instrument these
      # @param except [Array<Symbol>] blacklist - skip these
      # @return [Array<Symbol>] names of integrations that were instrumented
      #
      # @example Instrument all available
      #   Braintrust::Contrib.auto_instrument!
      #
      # @example Only specific integrations
      #   Braintrust::Contrib.auto_instrument!(only: [:openai, :anthropic])
      #
      # @example Exclude specific integrations
      #   Braintrust::Contrib.auto_instrument!(except: [:ruby_llm])
      def auto_instrument!(only: nil, except: nil)
        targets = registry.available
        targets = targets.select { |i| only.include?(i.integration_name) } if only
        targets = targets.reject { |i| except.include?(i.integration_name) } if except

        targets.each_with_object([]) do |integration, instrumented|
          instrumented << integration.integration_name if instrument!(integration.integration_name)
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

# Register integrations
Braintrust::Contrib::OpenAI::Integration.register!
