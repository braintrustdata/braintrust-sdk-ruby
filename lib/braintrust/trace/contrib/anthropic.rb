# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

module Braintrust
  module Trace
    module Anthropic
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

      # Parse usage tokens from Anthropic API response, handling cache tokens
      # Maps Anthropic field names to Braintrust standard names:
      # - input_tokens → contributes to prompt_tokens
      # - cache_creation_input_tokens → prompt_cache_creation_tokens (and adds to prompt_tokens)
      # - cache_read_input_tokens → prompt_cached_tokens (and adds to prompt_tokens)
      # - output_tokens → completion_tokens
      # - total_tokens → tokens (or calculated if missing)
      #
      # @param usage [Hash, Object] usage object from Anthropic response
      # @return [Hash<String, Integer>] metrics hash with normalized names
      def self.parse_usage_tokens(usage)
        metrics = {}
        return metrics unless usage

        # Convert to hash if it's an object
        usage_hash = usage.respond_to?(:to_h) ? usage.to_h : usage

        # Extract base values for calculation
        input_tokens = 0
        cache_creation_tokens = 0
        cache_read_tokens = 0

        usage_hash.each do |key, value|
          next unless value.is_a?(Numeric)
          key_str = key.to_s

          case key_str
          when "input_tokens"
            input_tokens = value.to_i
          when "cache_creation_input_tokens"
            cache_creation_tokens = value.to_i
            metrics["prompt_cache_creation_tokens"] = value.to_i
          when "cache_read_input_tokens"
            cache_read_tokens = value.to_i
            metrics["prompt_cached_tokens"] = value.to_i
          when "output_tokens"
            metrics["completion_tokens"] = value.to_i
          when "total_tokens"
            metrics["tokens"] = value.to_i
          else
            # Keep other numeric fields as-is (future-proofing)
            metrics[key_str] = value.to_i
          end
        end

        # Calculate total prompt tokens (input + cache creation + cache read)
        total_prompt_tokens = input_tokens + cache_creation_tokens + cache_read_tokens
        metrics["prompt_tokens"] = total_prompt_tokens

        # Calculate total tokens if not provided by Anthropic
        if !metrics.key?("tokens") && metrics.key?("completion_tokens")
          metrics["tokens"] = total_prompt_tokens + metrics["completion_tokens"]
        end

        metrics
      end

      # Wrap an Anthropic::Client to automatically create spans for messages and responses
      # Supports both synchronous and streaming requests
      # @param client [Anthropic::Client] the Anthropic client to wrap
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider (defaults to global)
      def self.wrap(client, tracer_provider: nil)
        tracer_provider ||= ::OpenTelemetry.tracer_provider

        # Wrap messages.create
        wrap_messages_create(client, tracer_provider)

        # Wrap messages.stream (Anthropic SDK always has this method)
        wrap_messages_stream(client, tracer_provider)

        client
      end

      # Wrap messages.create API
      # @param client [Anthropic::Client] the Anthropic client
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
      def self.wrap_messages_create(client, tracer_provider)
        # Create a wrapper module that intercepts messages.create
        wrapper = Module.new do
          define_method(:create) do |**params|
            tracer = tracer_provider.tracer("braintrust")

            tracer.in_span("anthropic.messages.create") do |span|
              # Initialize metadata hash
              metadata = {
                "provider" => "anthropic",
                "endpoint" => "/v1/messages"
              }

              # Capture request metadata fields
              metadata_fields = %i[
                model max_tokens temperature top_p top_k stop_sequences
                stream tools tool_choice thinking metadata service_tier
              ]

              metadata_fields.each do |field|
                metadata[field.to_s] = params[field] if params.key?(field)
              end

              # Build input messages array, prepending system prompt if present
              input_messages = []

              # Prepend system prompt as a message if present
              if params[:system]
                # System can be a string or array of text blocks
                system_content = params[:system]
                if system_content.is_a?(Array)
                  # Extract text from array of text blocks
                  system_text = system_content.map { |block|
                    block.is_a?(Hash) ? block[:text] : block
                  }.join("\n")
                  input_messages << {role: "system", content: system_text}
                else
                  input_messages << {role: "system", content: system_content}
                end
              end

              # Add user/assistant messages
              if params[:messages]
                messages_array = params[:messages].map(&:to_h)
                input_messages.concat(messages_array)
              end

              # Set input messages as JSON
              if input_messages.any?
                span.set_attribute("braintrust.input_json", JSON.generate(input_messages))
              end

              # Call the original method
              response = super(**params)

              # Format output as array of messages (same format as input)
              if response.respond_to?(:content) && response.content
                content_array = response.content.map(&:to_h)
                output = [{
                  role: response.respond_to?(:role) ? response.role : "assistant",
                  content: content_array
                }]
                span.set_attribute("braintrust.output_json", JSON.generate(output))
              end

              # Set metrics (token usage with Anthropic-specific cache tokens)
              if response.respond_to?(:usage) && response.usage
                metrics = Braintrust::Trace::Anthropic.parse_usage_tokens(response.usage)
                span.set_attribute("braintrust.metrics", JSON.generate(metrics)) unless metrics.empty?
              end

              # Add response metadata fields
              if response.respond_to?(:stop_reason) && response.stop_reason
                metadata["stop_reason"] = response.stop_reason
              end
              if response.respond_to?(:stop_sequence) && response.stop_sequence
                metadata["stop_sequence"] = response.stop_sequence
              end
              # Update model if present in response (in case it was resolved from "latest")
              if response.respond_to?(:model) && response.model
                metadata["model"] = response.model
              end

              # Set metadata ONCE at the end with complete hash
              span.set_attribute("braintrust.metadata", JSON.generate(metadata))

              response
            end
          end
        end

        # Prepend the wrapper to the messages resource
        client.messages.singleton_class.prepend(wrapper)
      end

      # Wrap messages.stream API
      # @param client [Anthropic::Client] the Anthropic client
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider] the tracer provider
      def self.wrap_messages_stream(client, tracer_provider)
        # Create a wrapper module that intercepts messages.stream
        wrapper = Module.new do
          define_method(:stream) do |**params, &block|
            tracer = tracer_provider.tracer("braintrust")

            metadata = {
              "provider" => "anthropic",
              "endpoint" => "/v1/messages",
              "stream" => true
            }

            # Start span with proper context
            span = tracer.start_span("anthropic.messages.create")

            # Capture request metadata fields
            metadata_fields = %i[
              model max_tokens temperature top_p top_k stop_sequences
              tools tool_choice thinking metadata service_tier
            ]

            metadata_fields.each do |field|
              metadata[field.to_s] = params[field] if params.key?(field)
            end

            # Build input messages array, prepending system prompt if present
            input_messages = []

            if params[:system]
              system_content = params[:system]
              if system_content.is_a?(Array)
                system_text = system_content.map { |block|
                  block.is_a?(Hash) ? block[:text] : block
                }.join("\n")
                input_messages << {role: "system", content: system_text}
              else
                input_messages << {role: "system", content: system_content}
              end
            end

            if params[:messages]
              messages_array = params[:messages].map(&:to_h)
              input_messages.concat(messages_array)
            end

            if input_messages.any?
              span.set_attribute("braintrust.input_json", JSON.generate(input_messages))
            end

            # Set initial metadata
            span.set_attribute("braintrust.metadata", JSON.generate(metadata))

            # Call the original stream method WITHOUT passing the block
            # We'll handle the block ourselves to aggregate events
            begin
              stream = super(**params)
            rescue => e
              span.record_exception(e)
              span.status = ::OpenTelemetry::Trace::Status.error("Anthropic API error: #{e.message}")
              span.finish
              raise
            end

            # Store references on the stream object itself for the wrapper
            stream.instance_variable_set(:@braintrust_span, span)
            stream.instance_variable_set(:@braintrust_metadata, metadata)
            stream.instance_variable_set(:@braintrust_span_finished, false)

            # Local helper for brevity
            set_json_attr = ->(attr_name, obj) { Braintrust::Trace::Anthropic.set_json_attr(span, attr_name, obj) }

            # Helper lambda to extract stream data and set span attributes
            # This is DRY - used by both .each() and .text() wrappers
            extract_stream_metadata = lambda do
              # Extract the SDK's internal accumulated message (built during streaming)
              acc_msg = stream.instance_variable_get(:@accumated_message_snapshot)
              return unless acc_msg

              # Set output from accumulated message
              if acc_msg.respond_to?(:content) && acc_msg.content
                content_array = acc_msg.content.map(&:to_h)
                output = [{
                  role: acc_msg.respond_to?(:role) ? acc_msg.role : "assistant",
                  content: content_array
                }]
                set_json_attr.call("braintrust.output_json", output)
              end

              # Set metrics from accumulated message
              if acc_msg.respond_to?(:usage) && acc_msg.usage
                metrics = Braintrust::Trace::Anthropic.parse_usage_tokens(acc_msg.usage)
                set_json_attr.call("braintrust.metrics", metrics) unless metrics.empty?
              end

              # Update metadata with response fields
              if acc_msg.respond_to?(:stop_reason) && acc_msg.stop_reason
                metadata["stop_reason"] = acc_msg.stop_reason
              end
              if acc_msg.respond_to?(:model) && acc_msg.model
                metadata["model"] = acc_msg.model
              end
              set_json_attr.call("braintrust.metadata", metadata)
            end

            # Helper lambda to finish span (prevents double-finishing via closure)
            finish_braintrust_span = lambda do
              return if stream.instance_variable_get(:@braintrust_span_finished)
              stream.instance_variable_set(:@braintrust_span_finished, true)

              extract_stream_metadata.call
              span.finish
            end

            # Wrap .each() to ensure span finishes after consumption
            original_each = stream.method(:each)
            stream.define_singleton_method(:each) do |&user_block|
              # Consume stream, calling user's block for each event
              # The SDK builds @accumated_message_snapshot internally
              original_each.call(&user_block)
            rescue => e
              span.record_exception(e)
              span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
              raise
            ensure
              # Extract accumulated message and finish span
              finish_braintrust_span.call
            end

            # Wrap .text() to return an Enumerable that ensures span finishes
            original_text = stream.method(:text)
            stream.define_singleton_method(:text) do
              text_enum = original_text.call

              # Return wrapper Enumerable that finishes span after consumption
              Enumerator.new do |y|
                # Consume text enumerable (this consumes underlying stream)
                # The SDK builds @accumated_message_snapshot internally
                text_enum.each { |text| y << text }
              rescue => e
                span.record_exception(e)
                span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
                raise
              ensure
                # Extract accumulated message and finish span
                finish_braintrust_span.call
              end
            end

            # Wrap .close() to ensure span finishes even if stream not consumed
            original_close = stream.method(:close)
            stream.define_singleton_method(:close) do
              original_close.call
            ensure
              # Finish span even if stream was closed early
              finish_braintrust_span.call
            end

            # If a block was provided to stream(), call each with it immediately
            if block
              stream.each(&block)
            end

            stream
          end
        end

        # Prepend the wrapper to the messages resource
        client.messages.singleton_class.prepend(wrapper)
      end
    end
  end
end
