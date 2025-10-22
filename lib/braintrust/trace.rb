# frozen_string_literal: true

require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require_relative "trace/span_processor"
require_relative "trace/openai"
require_relative "logger"

module Braintrust
  module Trace
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
        # For experiments: {app_url}/app/{org}/p/{project}/experiments/{experiment_id}?r={trace_id}&s={span_id}
        project_name, experiment_id = parent_id.split("/", 2)
        unless project_name && experiment_id
          Log.error("Invalid experiment parent format: #{parent_id}")
          return ""
        end

        "#{app_url}/app/#{org_name}/p/#{project_name}/experiments/#{experiment_id}?r=#{trace_id}&s=#{span_id}"
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
