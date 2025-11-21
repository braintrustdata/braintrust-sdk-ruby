# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

module Braintrust
  module Trace
    module Gemini
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

      # Parse usage tokens from Gemini API response
      # Maps Gemini field names to Braintrust standard names:
      # - promptTokenCount → prompt_tokens
      # - candidatesTokenCount → completion_tokens
      # - totalTokenCount → tokens (or calculated if missing)
      #
      # @param usage [Hash, Object] usage metadata from Gemini response
      # @return [Hash<String, Integer>] metrics hash with normalized names
      def self.parse_usage_tokens(usage)
        metrics = {}
        return metrics unless usage

        # Convert to hash if it's an object
        usage_hash = usage.respond_to?(:to_h) ? usage.to_h : usage

        usage_hash.each do |key, value|
          next unless value.is_a?(Numeric)
          key_str = key.to_s

          case key_str
          when "promptTokenCount"
            metrics["prompt_tokens"] = value.to_i
          when "candidatesTokenCount"
            metrics["completion_tokens"] = value.to_i
          when "totalTokenCount"
            metrics["tokens"] = value.to_i
          else
            # Keep other numeric fields as-is (future-proofing)
            metrics[key_str] = value.to_i
          end
        end

        # Calculate total tokens if not provided by Gemini
        if !metrics.key?("tokens") && metrics.key?("prompt_tokens") && metrics.key?("completion_tokens")
          metrics["tokens"] = metrics["prompt_tokens"] + metrics["completion_tokens"]
        end

        metrics
      end

      # Extract messages array from Gemini response
      # Converts Gemini's candidates array to standardized message format
      # @param response [Array<Hash>] Gemini API response
      # @return [Array<Hash>] array of messages in standard format
      def self.extract_output_messages(response)
        return [] unless response.is_a?(Array) && response.any?

        # Gemini returns array of response chunks, take the last one for non-streaming
        last_response = response.last
        return [] unless last_response.is_a?(Hash)

        candidates = last_response["candidates"]
        return [] unless candidates.is_a?(Array) && candidates.any?

        # Extract content from first candidate
        candidate = candidates.first
        content = candidate["content"]
        return [] unless content

        # Convert to standard message format
        [{
          "role" => content["role"],
          "parts" => content["parts"]
        }]
      end

      # Aggregate streaming chunks from Gemini into a single response structure
      # @param chunks [Array<Hash>] array of chunk hashes from stream
      # @return [Hash] aggregated response with candidates, usageMetadata, etc.
      def self.aggregate_streaming_chunks(chunks)
        return {} if chunks.empty?

        # Initialize aggregated structure
        aggregated = {
          "candidates" => [],
          "usageMetadata" => nil
        }

        # Track aggregated parts for each candidate index
        candidate_data = {}

        chunks.each do |chunk|
          # Aggregate usageMetadata (usually only in last chunk)
          if chunk["usageMetadata"]
            aggregated["usageMetadata"] = chunk["usageMetadata"]
          end

          # Process candidates
          next unless chunk["candidates"].is_a?(Array)
          chunk["candidates"].each do |candidate|
            index = candidate["index"] || 0
            candidate_data[index] ||= {
              "index" => index,
              "content" => {
                "role" => nil,
                "parts" => []
              },
              "finishReason" => nil,
              "safetyRatings" => nil
            }

            # Aggregate content
            if candidate["content"]
              content = candidate["content"]
              candidate_data[index]["content"]["role"] ||= content["role"]

              # Aggregate parts (text deltas)
              if content["parts"].is_a?(Array)
                content["parts"].each do |part|
                  if part["text"]
                    # Check if we need to append to last part or create new one
                    if candidate_data[index]["content"]["parts"].any? && candidate_data[index]["content"]["parts"].last["text"]
                      candidate_data[index]["content"]["parts"].last["text"] += part["text"]
                    else
                      candidate_data[index]["content"]["parts"] << {"text" => part["text"].dup}
                    end
                  else
                    # Non-text part (e.g., inline_data), add as-is
                    candidate_data[index]["content"]["parts"] << part
                  end
                end
              end
            end

            # Capture finishReason and safetyRatings
            if candidate["finishReason"]
              candidate_data[index]["finishReason"] = candidate["finishReason"]
            end
            if candidate["safetyRatings"]
              candidate_data[index]["safetyRatings"] = candidate["safetyRatings"]
            end
          end
        end

        # Build final candidates array
        aggregated["candidates"] = candidate_data.values.sort_by { |c| c["index"] }

        aggregated
      end

      # Wrap a Gemini::Client to automatically create spans for generate_content and stream_generate_content
      # Supports both synchronous and streaming requests
      # @param client [Gemini::Client] the Gemini client to wrap
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
      def self.wrap(client, tracer_provider: nil)
        tracer_provider ||= ::OpenTelemetry.tracer_provider

        # Wrap generate_content (non-streaming)
        wrap_generate_content(client, tracer_provider)

        # Wrap stream_generate_content (streaming)
        wrap_stream_generate_content(client, tracer_provider)

        client
      end

      # Wrap generate_content API (non-streaming)
      # @param client [Gemini::Client] the Gemini client
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
      def self.wrap_generate_content(client, tracer_provider)
        # Create a wrapper module that intercepts generate_content
        wrapper = Module.new do
          define_method(:generate_content) do |params|
            tracer = tracer_provider.tracer("braintrust")

            tracer.in_span("gemini.generate_content") do |span|
              # Initialize metadata hash
              metadata = {
                "provider" => "gemini",
                "endpoint" => "/generateContent"
              }

              # Extract model from client options
              if @options && @options[:model]
                metadata["model"] = @options[:model]
              end

              # Extract request parameters
              metadata_fields = %i[
                temperature top_p top_k max_output_tokens stop_sequences
                candidate_count safety_settings generation_config
              ]

              metadata_fields.each do |field|
                metadata[field.to_s] = params[field] if params.key?(field)
              end

              # Set input messages as JSON
              # Normalize contents to array format
              if params[:contents]
                contents_array = params[:contents].is_a?(Array) ? params[:contents] : [params[:contents]]
                messages_array = contents_array.map do |content|
                  if content.is_a?(Hash)
                    content
                  else
                    content.respond_to?(:to_h) ? content.to_h : content
                  end
                end
                span.set_attribute("braintrust.input_json", JSON.generate(messages_array))
              end

              # Set initial metadata
              span.set_attribute("braintrust.metadata", JSON.generate(metadata))

              # Call the original method
              begin
                response = super(params)
              rescue => e
                # Record exception and re-raise
                span.record_exception(e)
                span.status = ::OpenTelemetry::Trace::Status.error("Gemini API error: #{e.message}")
                raise
              end

              # Set output messages as JSON
              output_messages = Braintrust::Trace::Gemini.extract_output_messages(response)
              if output_messages.any?
                span.set_attribute("braintrust.output_json", JSON.generate(output_messages))
              end

              # Set metrics (token usage)
              if response.is_a?(Array) && response.any?
                last_response = response.last
                if last_response.is_a?(Hash) && last_response["usageMetadata"]
                  metrics = Braintrust::Trace::Gemini.parse_usage_tokens(last_response["usageMetadata"])
                  span.set_attribute("braintrust.metrics", JSON.generate(metrics)) unless metrics.empty?
                end
              end

              response
            end
          end
        end

        # Prepend the wrapper to the client's singleton class
        client.singleton_class.prepend(wrapper)
      end

      # Wrap stream_generate_content API (streaming)
      # @param client [Gemini::Client] the Gemini client
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
      def self.wrap_stream_generate_content(client, tracer_provider)
        # Create a wrapper module that intercepts stream_generate_content
        wrapper = Module.new do
          define_method(:stream_generate_content) do |params|
            tracer = tracer_provider.tracer("braintrust")
            aggregated_chunks = []
            metadata = {
              "provider" => "gemini",
              "endpoint" => "/generateContent",
              "stream" => true
            }

            # Start span with proper context
            span = tracer.start_span("gemini.generate_content")

            # Extract model from client options
            if @options && @options[:model]
              metadata["model"] = @options[:model]
            end

            # Extract request parameters
            metadata_fields = %i[
              temperature top_p top_k max_output_tokens stop_sequences
              candidate_count safety_settings generation_config
            ]

            metadata_fields.each do |field|
              metadata[field.to_s] = params[field] if params.key?(field)
            end

            # Set input messages as JSON
            if params[:contents]
              contents_array = params[:contents].is_a?(Array) ? params[:contents] : [params[:contents]]
              messages_array = contents_array.map do |content|
                if content.is_a?(Hash)
                  content
                else
                  content.respond_to?(:to_h) ? content.to_h : content
                end
              end
              span.set_attribute("braintrust.input_json", JSON.generate(messages_array))
            end

            # Set initial metadata
            span.set_attribute("braintrust.metadata", JSON.generate(metadata))

            # Call the original stream method with error handling
            begin
              result = super(params)
            rescue => e
              # Record exception if stream creation fails
              span.record_exception(e)
              span.status = ::OpenTelemetry::Trace::Status.error("Gemini API error: #{e.message}")
              span.finish
              raise
            end

            # For Gemini, the streaming result is returned as an array immediately
            # We need to aggregate all chunks
            begin
              if result.is_a?(Array)
                aggregated_chunks = result.map { |chunk| chunk.is_a?(Hash) ? chunk : chunk.to_h }

                # Aggregate chunks into single response
                unless aggregated_chunks.empty?
                  aggregated_output = Braintrust::Trace::Gemini.aggregate_streaming_chunks(aggregated_chunks)

                  # Set output from aggregated candidates
                  if aggregated_output["candidates"]&.any?
                    output_messages = [{
                      "role" => aggregated_output["candidates"].first["content"]["role"],
                      "parts" => aggregated_output["candidates"].first["content"]["parts"]
                    }]
                    Braintrust::Trace::Gemini.set_json_attr(span, "braintrust.output_json", output_messages)
                  end

                  # Set metrics if usage is included
                  if aggregated_output["usageMetadata"]
                    metrics = Braintrust::Trace::Gemini.parse_usage_tokens(aggregated_output["usageMetadata"])
                    Braintrust::Trace::Gemini.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
                  end
                end
              end
            rescue => e
              # Record exception if aggregation fails
              span.record_exception(e)
              span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
            ensure
              span.finish
            end

            result
          end
        end

        # Prepend the wrapper to the client's singleton class
        client.singleton_class.prepend(wrapper)
      end
    end
  end
end
