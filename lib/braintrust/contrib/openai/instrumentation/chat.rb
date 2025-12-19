# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

require_relative "common"

module Braintrust
  module Contrib
    module OpenAI
      module Instrumentation
        # Chat completions instrumentation for OpenAI.
        # Provides modules that can be prepended to OpenAI::Client to instrument chat.completions API.
        module Chat
          # Module prepended to chat.completions to add tracing
          module Completions
            def self.included(base)
              # Guard against double-wrapping for: Check if patch is already in the ancestor chain.
              # This prevents double instrumentation if class-level patching was already applied,
              # and this patch is being applied to a singleton-class. (Special case.)
              #
              # Ruby's prepend() doesn't check the full inheritance chain, so without this guard,
              # the instrumentation could be added twice.
              base.prepend(InstanceMethods) unless applied?(base)
            end

            def self.applied?(base)
              base.ancestors.include?(InstanceMethods)
            end

            module InstanceMethods
              # Wrap create method for non-streaming completions
              def create(**params)
                client = instance_variable_get(:@client)
                tracer = Braintrust::Contrib.tracer_for(client)

                tracer.in_span("Chat Completion") do |span|
                  # Track start time for time_to_first_token
                  start_time = Time.now

                  # Initialize metadata hash
                  metadata = {
                    "provider" => "openai",
                    "endpoint" => "/v1/chat/completions"
                  }

                  # Capture request metadata fields
                  metadata_fields = %i[
                    model frequency_penalty logit_bias logprobs max_tokens n
                    presence_penalty response_format seed service_tier stop
                    stream stream_options temperature top_p top_logprobs
                    tools tool_choice parallel_tool_calls user functions function_call
                  ]

                  metadata_fields.each do |field|
                    metadata[field.to_s] = params[field] if params.key?(field)
                  end

                  # Set input messages as JSON
                  if params[:messages]
                    messages_array = params[:messages].map(&:to_h)
                    span.set_attribute("braintrust.input_json", JSON.generate(messages_array))
                  end

                  # Call the original method
                  response = super(**params)

                  # Calculate time to first token
                  time_to_first_token = Time.now - start_time

                  # Set output (choices) as JSON
                  if response.respond_to?(:choices) && response.choices&.any?
                    choices_array = response.choices.map(&:to_h)
                    span.set_attribute("braintrust.output_json", JSON.generate(choices_array))
                  end

                  # Set metrics (token usage with advanced details)
                  metrics = {}
                  if response.respond_to?(:usage) && response.usage
                    metrics = Common.parse_usage_tokens(response.usage)
                  end
                  # Add time_to_first_token metric
                  metrics["time_to_first_token"] = time_to_first_token
                  span.set_attribute("braintrust.metrics", JSON.generate(metrics)) unless metrics.empty?

                  # Add response metadata fields
                  metadata["id"] = response.id if response.respond_to?(:id) && response.id
                  metadata["created"] = response.created if response.respond_to?(:created) && response.created
                  metadata["system_fingerprint"] = response.system_fingerprint if response.respond_to?(:system_fingerprint) && response.system_fingerprint
                  metadata["service_tier"] = response.service_tier if response.respond_to?(:service_tier) && response.service_tier

                  # Set metadata ONCE at the end with complete hash
                  span.set_attribute("braintrust.metadata", JSON.generate(metadata))

                  response
                end
              end

              # Wrap stream_raw for streaming chat completions
              def stream_raw(**params)
                client = instance_variable_get(:@client)
                tracer = Braintrust::Contrib.tracer_for(client)
                aggregated_chunks = []
                start_time = Time.now
                time_to_first_token = nil
                metadata = {
                  "provider" => "openai",
                  "endpoint" => "/v1/chat/completions"
                }

                # Start span with proper context
                span = tracer.start_span("Chat Completion")

                # Capture request metadata fields
                metadata_fields = %i[
                  model frequency_penalty logit_bias logprobs max_tokens n
                  presence_penalty response_format seed service_tier stop
                  stream stream_options temperature top_p top_logprobs
                  tools tool_choice parallel_tool_calls user functions function_call
                ]

                metadata_fields.each do |field|
                  metadata[field.to_s] = params[field] if params.key?(field)
                end
                metadata["stream"] = true # Explicitly mark as streaming

                # Set input messages as JSON
                if params[:messages]
                  messages_array = params[:messages].map(&:to_h)
                  span.set_attribute("braintrust.input_json", JSON.generate(messages_array))
                end

                # Set initial metadata
                span.set_attribute("braintrust.metadata", JSON.generate(metadata))

                # Call the original stream_raw method with error handling
                begin
                  stream = super
                rescue => e
                  # Record exception if stream creation fails
                  span.record_exception(e)
                  span.status = ::OpenTelemetry::Trace::Status.error("OpenAI API error: #{e.message}")
                  span.finish
                  raise
                end

                # Wrap the stream to aggregate chunks
                original_each = stream.method(:each)
                stream.define_singleton_method(:each) do |&block|
                  original_each.call do |chunk|
                    # Capture time to first token on first chunk
                    time_to_first_token ||= Time.now - start_time
                    aggregated_chunks << chunk.to_h
                    block&.call(chunk)
                  end
                rescue => e
                  # Record exception if streaming fails
                  span.record_exception(e)
                  span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
                  raise
                ensure
                  # Always aggregate whatever chunks we collected and finish span
                  unless aggregated_chunks.empty?
                    aggregated_output = Common.aggregate_streaming_chunks(aggregated_chunks)
                    Common.set_json_attr(span, "braintrust.output_json", aggregated_output[:choices])

                    # Set metrics if usage is included
                    metrics = {}
                    if aggregated_output[:usage]
                      metrics = Common.parse_usage_tokens(aggregated_output[:usage])
                    end
                    # Add time_to_first_token metric
                    metrics["time_to_first_token"] = time_to_first_token || 0.0
                    Common.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?

                    # Update metadata with response fields
                    metadata["id"] = aggregated_output[:id] if aggregated_output[:id]
                    metadata["created"] = aggregated_output[:created] if aggregated_output[:created]
                    metadata["model"] = aggregated_output[:model] if aggregated_output[:model]
                    metadata["system_fingerprint"] = aggregated_output[:system_fingerprint] if aggregated_output[:system_fingerprint]
                    Common.set_json_attr(span, "braintrust.metadata", metadata)
                  end

                  span.finish
                end

                stream
              end

              # Wrap stream for streaming chat completions (returns ChatCompletionStream with convenience methods)
              def stream(**params)
                client = instance_variable_get(:@client)
                tracer = Braintrust::Contrib.tracer_for(client)
                start_time = Time.now
                time_to_first_token = nil
                metadata = {
                  "provider" => "openai",
                  "endpoint" => "/v1/chat/completions"
                }

                # Start span with proper context
                span = tracer.start_span("Chat Completion")

                # Capture request metadata fields
                metadata_fields = %i[
                  model frequency_penalty logit_bias logprobs max_tokens n
                  presence_penalty response_format seed service_tier stop
                  stream stream_options temperature top_p top_logprobs
                  tools tool_choice parallel_tool_calls user functions function_call
                ]

                metadata_fields.each do |field|
                  metadata[field.to_s] = params[field] if params.key?(field)
                end
                metadata["stream"] = true # Explicitly mark as streaming

                # Set input messages as JSON
                if params[:messages]
                  messages_array = params[:messages].map(&:to_h)
                  span.set_attribute("braintrust.input_json", JSON.generate(messages_array))
                end

                # Set initial metadata
                span.set_attribute("braintrust.metadata", JSON.generate(metadata))

                # Call the original stream method with error handling
                begin
                  stream = super
                rescue => e
                  # Record exception if stream creation fails
                  span.record_exception(e)
                  span.status = ::OpenTelemetry::Trace::Status.error("OpenAI API error: #{e.message}")
                  span.finish
                  raise
                end

                # Local helper for setting JSON attributes
                set_json_attr = ->(attr_name, obj) { Common.set_json_attr(span, attr_name, obj) }

                # Helper to extract metadata from SDK's internal snapshot
                extract_stream_metadata = lambda do
                  # Access the SDK's internal accumulated completion snapshot
                  snapshot = stream.current_completion_snapshot
                  return unless snapshot

                  # Set output from accumulated choices
                  if snapshot.choices&.any?
                    choices_array = snapshot.choices.map(&:to_h)
                    set_json_attr.call("braintrust.output_json", choices_array)
                  end

                  # Set metrics if usage is available
                  metrics = {}
                  if snapshot.usage
                    metrics = Common.parse_usage_tokens(snapshot.usage)
                  end
                  # Add time_to_first_token metric
                  metrics["time_to_first_token"] = time_to_first_token || 0.0
                  set_json_attr.call("braintrust.metrics", metrics) unless metrics.empty?

                  # Update metadata with response fields
                  metadata["id"] = snapshot.id if snapshot.respond_to?(:id) && snapshot.id
                  metadata["created"] = snapshot.created if snapshot.respond_to?(:created) && snapshot.created
                  metadata["model"] = snapshot.model if snapshot.respond_to?(:model) && snapshot.model
                  metadata["system_fingerprint"] = snapshot.system_fingerprint if snapshot.respond_to?(:system_fingerprint) && snapshot.system_fingerprint
                  set_json_attr.call("braintrust.metadata", metadata)
                end

                # Prevent double-finish of span
                finish_braintrust_span = lambda do
                  return if stream.instance_variable_get(:@braintrust_span_finished)
                  stream.instance_variable_set(:@braintrust_span_finished, true)
                  extract_stream_metadata.call
                  span.finish
                end

                # Wrap .each() method - this is the core consumption method
                original_each = stream.method(:each)
                stream.define_singleton_method(:each) do |&block|
                  original_each.call do |chunk|
                    # Capture time to first token on first chunk
                    time_to_first_token ||= Time.now - start_time
                    block&.call(chunk)
                  end
                rescue => e
                  span.record_exception(e)
                  span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
                  raise
                ensure
                  finish_braintrust_span.call
                end

                # Wrap .text() method - returns enumerable for text deltas
                original_text = stream.method(:text)
                stream.define_singleton_method(:text) do
                  text_enum = original_text.call
                  # Wrap the returned enumerable's .each method
                  original_text_each = text_enum.method(:each)
                  text_enum.define_singleton_method(:each) do |&block|
                    original_text_each.call do |delta|
                      # Capture time to first token on first delta
                      time_to_first_token ||= Time.now - start_time
                      block&.call(delta)
                    end
                  rescue => e
                    span.record_exception(e)
                    span.status = ::OpenTelemetry::Trace::Status.error("Streaming error: #{e.message}")
                    raise
                  ensure
                    finish_braintrust_span.call
                  end
                  text_enum
                end

                stream
              end
            end
          end
        end
      end
    end
  end
end
