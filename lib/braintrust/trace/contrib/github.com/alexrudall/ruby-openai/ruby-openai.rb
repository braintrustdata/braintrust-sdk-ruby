# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"
require_relative "../../../../tokens"

module Braintrust
  module Trace
    module Contrib
      module Github
        module Alexrudall
          module RubyOpenAI
            # Helper to safely set a JSON attribute on a span
            # Only sets the attribute if obj is present
            # @param span [OpenTelemetry::Trace::Span] the span to set attribute on
            # @param attr_name [String] the attribute name (e.g., "braintrust.output_json")
            # @param obj [Object] the object to serialize to JSON
            # @return [void]
            def self.set_json_attr(span, attr_name, obj)
              return unless obj
              span.set_attribute(attr_name, JSON.generate(obj))
            end

            # Parse usage tokens from OpenAI API response
            # @param usage [Hash] usage hash from OpenAI response
            # @return [Hash<String, Integer>] metrics hash with normalized names
            def self.parse_usage_tokens(usage)
              Braintrust::Trace.parse_openai_usage_tokens(usage)
            end

            # Aggregate streaming chunks into a single response structure
            # @param chunks [Array<Hash>] array of chunk hashes from stream
            # @return [Hash] aggregated response with choices, usage, id, created, model
            def self.aggregate_streaming_chunks(chunks)
              return {} if chunks.empty?

              # Initialize aggregated structure
              aggregated = {
                "id" => nil,
                "created" => nil,
                "model" => nil,
                "usage" => nil,
                "choices" => []
              }

              # Track aggregated content for the first choice
              role = nil
              content = +""

              chunks.each do |chunk|
                # Capture top-level fields from any chunk that has them
                aggregated["id"] ||= chunk["id"]
                aggregated["created"] ||= chunk["created"]
                aggregated["model"] ||= chunk["model"]

                # Aggregate usage (usually only in last chunk if stream_options.include_usage is set)
                aggregated["usage"] = chunk["usage"] if chunk["usage"]

                # Aggregate content from first choice
                if chunk.dig("choices", 0, "delta", "role")
                  role ||= chunk.dig("choices", 0, "delta", "role")
                end
                if chunk.dig("choices", 0, "delta", "content")
                  content << chunk.dig("choices", 0, "delta", "content")
                end
              end

              # Build aggregated choices array
              aggregated["choices"] = [
                {
                  "index" => 0,
                  "message" => {
                    "role" => role || "assistant",
                    "content" => content
                  },
                  "finish_reason" => chunks.dig(-1, "choices", 0, "finish_reason")
                }
              ]

              aggregated
            end

            # Set span attributes from response data (works for both streaming and non-streaming)
            # @param span [OpenTelemetry::Trace::Span] the span to set attributes on
            # @param response_data [Hash] response hash with keys: choices, usage, id, created, model, system_fingerprint, service_tier
            # @param time_to_first_token [Float] time to first token in seconds
            # @param metadata [Hash] metadata hash to update with response fields
            def self.set_span_attributes(span, response_data, time_to_first_token, metadata)
              # Set output (choices) as JSON
              if response_data["choices"]&.any?
                set_json_attr(span, "braintrust.output_json", response_data["choices"])
              end

              # Set metrics (token usage + time_to_first_token)
              metrics = {}
              if response_data["usage"]
                metrics = parse_usage_tokens(response_data["usage"])
              end
              metrics["time_to_first_token"] = time_to_first_token || 0.0
              set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?

              # Update metadata with response fields
              %w[id created model system_fingerprint service_tier].each do |field|
                metadata[field] = response_data[field] if response_data[field]
              end
            end

            # Wrap an OpenAI::Client (ruby-openai gem) to automatically create spans
            # Supports both synchronous and streaming requests
            # @param client [OpenAI::Client] the OpenAI client to wrap
            # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
            def self.wrap(client, tracer_provider: nil)
              tracer_provider ||= ::OpenTelemetry.tracer_provider

              # Wrap chat completions
              wrap_chat(client, tracer_provider)

              client
            end

            # Wrap chat API
            # @param client [OpenAI::Client] the OpenAI client
            # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
            def self.wrap_chat(client, tracer_provider)
              # Capture reference to helper methods for use inside wrapper
              ruby_openai_module = self

              # Create a wrapper module that intercepts the chat method
              wrapper = Module.new do
                define_method(:chat) do |parameters:|
                  tracer = tracer_provider.tracer("braintrust")

                  tracer.in_span("Chat Completion") do |span|
                    # Local helper for setting JSON attributes
                    set_json_attr = ->(attr_name, obj) { ruby_openai_module.set_json_attr(span, attr_name, obj) }

                    # Track start time for time_to_first_token
                    start_time = Time.now
                    time_to_first_token = nil
                    is_streaming = parameters.key?(:stream) && parameters[:stream].is_a?(Proc)

                    # Initialize metadata hash
                    metadata = {
                      "provider" => "openai",
                      "endpoint" => "/v1/chat/completions"
                    }

                    # Capture request metadata fields
                    metadata_fields = %w[
                      model frequency_penalty logit_bias logprobs max_tokens n
                      presence_penalty response_format seed service_tier stop
                      stream stream_options temperature top_p top_logprobs
                      tools tool_choice parallel_tool_calls user functions function_call
                    ]

                    metadata_fields.each do |field|
                      field_sym = field.to_sym
                      if parameters.key?(field_sym)
                        # Special handling for stream parameter (it's a Proc)
                        metadata[field] = if field == "stream"
                          true  # Just mark as streaming
                        else
                          parameters[field_sym]
                        end
                      end
                    end

                    # Set input messages as JSON
                    if parameters[:messages]
                      set_json_attr.call("braintrust.input_json", parameters[:messages])
                    end

                    # Wrap streaming callback if present to capture time to first token and aggregate chunks
                    aggregated_chunks = []
                    if is_streaming
                      original_stream_proc = parameters[:stream]
                      parameters = parameters.dup
                      parameters[:stream] = proc do |chunk, bytesize|
                        # Capture time to first token on first chunk
                        time_to_first_token ||= Time.now - start_time
                        # Aggregate chunks for later processing
                        aggregated_chunks << chunk
                        # Call original callback
                        original_stream_proc.call(chunk, bytesize)
                      end
                    end

                    begin
                      # Call the original method
                      response = super(parameters: parameters)

                      # Calculate time to first token for non-streaming
                      time_to_first_token ||= Time.now - start_time unless is_streaming

                      # Process response data
                      if is_streaming && !aggregated_chunks.empty?
                        # Aggregate streaming chunks into response-like structure
                        aggregated_response = Braintrust::Trace::Contrib::Github::Alexrudall::RubyOpenAI.aggregate_streaming_chunks(aggregated_chunks)
                        Braintrust::Trace::Contrib::Github::Alexrudall::RubyOpenAI.set_span_attributes(span, aggregated_response, time_to_first_token, metadata)
                      else
                        # Non-streaming: use response object directly
                        Braintrust::Trace::Contrib::Github::Alexrudall::RubyOpenAI.set_span_attributes(span, response || {}, time_to_first_token, metadata)
                      end

                      # Set metadata ONCE at the end with complete hash
                      set_json_attr.call("braintrust.metadata", metadata)

                      response
                    rescue => e
                      # Record exception in span
                      span.record_exception(e)
                      span.status = OpenTelemetry::Trace::Status.error("Exception: #{e.class} - #{e.message}")
                      raise
                    end
                  end
                end
              end

              # Prepend the wrapper to the client's singleton class
              client.singleton_class.prepend(wrapper)
            end
          end
        end
      end
    end

    # Backwards compatibility: this module was originally at Braintrust::Trace::AlexRudall::RubyOpenAI
    module AlexRudall
      RubyOpenAI = Contrib::Github::Alexrudall::RubyOpenAI
    end
  end
end
