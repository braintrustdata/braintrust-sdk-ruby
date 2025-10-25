# frozen_string_literal: true

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require_relative "trace/span_processor"
require_relative "logger"

# OpenAI integration is optional - automatically loaded if openai gem is available
begin
  require "openai"
  require_relative "trace/contrib/openai"
rescue LoadError
  # OpenAI gem not installed - integration will not be available
end

module Braintrust
  module Trace
    # Set up OpenTelemetry tracing with Braintrust
    # @param state [State] Braintrust state
    # @param tracer_provider [TracerProvider, nil] Optional tracer provider
    # @return [void]
    def self.setup(state, tracer_provider = nil)
      if tracer_provider
        # Use the explicitly provided tracer provider
        # DO NOT set as global - user is managing it themselves
        Log.debug("Using explicitly provided OpenTelemetry tracer provider")
      else
        # Check if global tracer provider is already a real TracerProvider
        current_provider = OpenTelemetry.tracer_provider

        if current_provider.is_a?(OpenTelemetry::SDK::Trace::TracerProvider)
          # Use existing provider
          Log.debug("Using existing OpenTelemetry tracer provider")
          tracer_provider = current_provider
        else
          # Create new provider and set as global
          tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
          OpenTelemetry.tracer_provider = tracer_provider
          Log.debug("Created OpenTelemetry tracer provider")
        end
      end

      # Enable Braintrust tracing (adds span processor)
      enable(tracer_provider, state: state)
    end

    def self.enable(tracer_provider, state: nil, exporter: nil)
      state ||= Braintrust.current_state
      raise Error, "No state available" unless state

      # Create OTLP HTTP exporter unless override provided
      exporter ||= OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: "#{state.api_url}/otel/v1/traces",
        headers: {
          "Authorization" => "Bearer #{state.api_key}"
        }
      )

      # Wrap in batch processor
      batch_processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)

      # Wrap batch processor in our custom span processor to add Braintrust attributes
      processor = SpanProcessor.new(batch_processor, state)

      # Register with tracer provider
      tracer_provider.add_span_processor(processor)

      # Console debug if enabled
      if ENV["BRAINTRUST_ENABLE_TRACE_CONSOLE_LOG"]
        console_exporter = OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
        console_processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(console_exporter)
        tracer_provider.add_span_processor(console_processor)
      end

      self
    end

    # Generate a permalink URL for a span to view in the Braintrust UI
    # Returns an empty string if the permalink cannot be generated
    # @param span [OpenTelemetry::Trace::Span] The span to generate a permalink for
    # @return [String] The permalink URL, or empty string if an error occurs
    def self.permalink(span)
      return "" if span.nil?

      # Extract required attributes from span
      span_context = span.context
      trace_id = span_context.hex_trace_id
      span_id = span_context.hex_span_id

      # Get Braintrust attributes
      attributes = span.attributes if span.respond_to?(:attributes)
      unless attributes
        Log.error("Span does not support attributes")
        return ""
      end

      app_url = attributes[SpanProcessor::APP_URL_ATTR_KEY]
      org_name = attributes[SpanProcessor::ORG_ATTR_KEY]
      parent = attributes[SpanProcessor::PARENT_ATTR_KEY]

      # Validate required attributes
      unless app_url
        Log.error("Missing required attribute: #{SpanProcessor::APP_URL_ATTR_KEY}")
        return ""
      end

      unless org_name
        Log.error("Missing required attribute: #{SpanProcessor::ORG_ATTR_KEY}")
        return ""
      end

      unless parent
        Log.error("Missing required attribute: #{SpanProcessor::PARENT_ATTR_KEY}")
        return ""
      end

      # Parse parent to determine URL format
      parent_type, parent_id = parent.split(":", 2)
      unless parent_type && parent_id
        Log.error("Invalid parent format: #{parent}")
        return ""
      end

      # Build the permalink URL based on parent type
      if parent_type == "experiment_id"
        # For experiments: {app_url}/app/{org}/object?object_type=experiment&object_id={experiment_id}&r={trace_id}&s={span_id}
        "#{app_url}/app/#{org_name}/object?object_type=experiment&object_id=#{parent_id}&r=#{trace_id}&s=#{span_id}"
      else
        # For projects: {app_url}/app/{org}/p/{project}/logs?r={trace_id}&s={span_id}
        # parent_type is typically "project_name"
        "#{app_url}/app/#{org_name}/p/#{parent_id}/logs?r=#{trace_id}&s=#{span_id}"
      end
    rescue => e
      Log.error("Failed to generate permalink: #{e.message}")
      ""
    end
  end
end
