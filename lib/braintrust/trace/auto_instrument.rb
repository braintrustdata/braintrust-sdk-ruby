# frozen_string_literal: true

require_relative "contrib/openai"
require_relative "contrib/anthropic"

module Braintrust
  module Trace
    # AutoInstrument module handles automatic instrumentation of supported libraries
    module AutoInstrument
      # Registry of supported libraries
      LIBRARIES = {
        openai: {
          class_name: "OpenAI::Client",
          wrapper_module: Braintrust::Trace::OpenAI
        },
        anthropic: {
          class_name: "Anthropic::Client",
          wrapper_module: Braintrust::Trace::Anthropic
        }
      }.freeze

      # Main entry point for auto-instrumentation
      # @param config [Hash] autoinstrument configuration
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider]
      def self.setup(config, tracer_provider)
        return unless config[:enabled]

        libraries_to_instrument = determine_libraries(config)
        libraries_to_instrument.each do |lib|
          instrument_library(lib, tracer_provider)
        end
      end

      # Determine which libraries to instrument based on config
      # @param config [Hash] autoinstrument configuration
      # @return [Array<Symbol>] list of library symbols to instrument
      def self.determine_libraries(config)
        if config[:include]
          config[:include] & LIBRARIES.keys  # Only included libs
        elsif config[:exclude]
          LIBRARIES.keys - config[:exclude]  # All except excluded
        else
          LIBRARIES.keys  # All libraries
        end
      end

      private_class_method :determine_libraries

      # Instrument a specific library if available
      # @param lib [Symbol] library symbol (:openai, :anthropic)
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider]
      def self.instrument_library(lib, tracer_provider)
        lib_config = LIBRARIES[lib]
        return unless library_available?(lib_config[:class_name])

        case lib
        when :openai then instrument_openai(tracer_provider)
        when :anthropic then instrument_anthropic(tracer_provider)
        end
      rescue => e
        Log.warn("Failed to auto-instrument #{lib}: #{e.message}")
      end

      private_class_method :instrument_library

      # Check if library is available
      # @param class_name [String] fully-qualified class name (e.g., "OpenAI::Client")
      # @return [Boolean] true if the class exists
      def self.library_available?(class_name)
        parts = class_name.split("::")
        parts.reduce(Object) do |mod, part|
          return false unless mod.const_defined?(part)
          mod.const_get(part)
        end
        true
      rescue NameError
        false
      end

      private_class_method :library_available?

      # Instrument OpenAI::Client
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider]
      def self.instrument_openai(tracer_provider)
        wrapper = Module.new do
          define_method(:initialize) do |*args, **kwargs, &block|
            super(*args, **kwargs, &block)
            Braintrust::Trace::OpenAI.wrap(self, tracer_provider: tracer_provider)
            self
          end
        end

        ::OpenAI::Client.prepend(wrapper)
        Log.debug("Auto-instrumented OpenAI::Client")
      end

      private_class_method :instrument_openai

      # Instrument Anthropic::Client
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider]
      def self.instrument_anthropic(tracer_provider)
        wrapper = Module.new do
          define_method(:initialize) do |*args, **kwargs, &block|
            super(*args, **kwargs, &block)
            Braintrust::Trace::Anthropic.wrap(self, tracer_provider: tracer_provider)
            self
          end
        end

        ::Anthropic::Client.prepend(wrapper)
        Log.debug("Auto-instrumented Anthropic::Client")
      end

      private_class_method :instrument_anthropic
    end
  end
end
