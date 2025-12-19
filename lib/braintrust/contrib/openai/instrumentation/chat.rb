# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

require_relative "common"
require_relative "../../../internal/time"

module Braintrust
  module Contrib
    module OpenAI
      module Instrumentation
        # Chat completions instrumentation for OpenAI.
        # Wraps create(), stream(), and stream_raw() methods to create spans.
        module Chat
          module Completions
            def self.included(base)
              base.prepend(InstanceMethods) unless applied?(base)
            end

            def self.applied?(base)
              base.ancestors.include?(InstanceMethods)
            end

            METADATA_FIELDS = %i[
              model frequency_penalty logit_bias logprobs max_tokens n
              presence_penalty response_format seed service_tier stop
              stream stream_options temperature top_p top_logprobs
              tools tool_choice parallel_tool_calls user functions function_call
            ].freeze

            module InstanceMethods
              # Wrap create method for non-streaming completions
              def create(**params)
                client = instance_variable_get(:@client)
                tracer = Braintrust::Contrib.tracer_for(client)

                tracer.in_span("Chat Completion") do |span|
                  metadata = build_metadata(params)

                  set_input(span, params)

                  response = nil
                  time_to_first_token = Braintrust::Internal::Time.measure do
                    response = super
                  end

                  set_output(span, response)
                  set_metrics(span, response, time_to_first_token)
                  finalize_metadata(span, metadata, response)

                  response
                end
              end

              # Wrap stream_raw for streaming chat completions (returns Internal::Stream)
              # Stores context on stream object for span creation during consumption
              def stream_raw(**params)
                client = instance_variable_get(:@client)
                tracer = Braintrust::Contrib.tracer_for(client)
                metadata = build_metadata(params, stream: true)

                stream_obj = super
                Braintrust::Contrib::Context.set!(stream_obj,
                  tracer: tracer,
                  params: params,
                  metadata: metadata,
                  completions_instance: self,
                  stream_type: :raw)
                stream_obj
              end

              # Wrap stream for streaming chat completions (returns ChatCompletionStream)
              # Stores context on stream object for span creation during consumption
              def stream(**params)
                client = instance_variable_get(:@client)
                tracer = Braintrust::Contrib.tracer_for(client)
                metadata = build_metadata(params, stream: true)

                stream_obj = super
                Braintrust::Contrib::Context.set!(stream_obj,
                  tracer: tracer,
                  params: params,
                  metadata: metadata,
                  completions_instance: self,
                  stream_type: :chat_completion)
                stream_obj
              end

              private

              def build_metadata(params, stream: false)
                metadata = {
                  "provider" => "openai",
                  "endpoint" => "/v1/chat/completions"
                }
                metadata["stream"] = true if stream
                Completions::METADATA_FIELDS.each do |field|
                  metadata[field.to_s] = params[field] if params.key?(field)
                end
                metadata
              end

              def set_input(span, params)
                return unless params[:messages]

                messages_array = params[:messages].map(&:to_h)
                Common.set_json_attr(span, "braintrust.input_json", messages_array)
              end

              def set_output(span, response)
                return unless response.respond_to?(:choices) && response.choices&.any?

                choices_array = response.choices.map(&:to_h)
                Common.set_json_attr(span, "braintrust.output_json", choices_array)
              end

              def set_metrics(span, response, time_to_first_token)
                metrics = {}
                if response.respond_to?(:usage) && response.usage
                  metrics = Common.parse_usage_tokens(response.usage)
                end
                metrics["time_to_first_token"] = time_to_first_token
                Common.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
              end

              def finalize_metadata(span, metadata, response)
                metadata["id"] = response.id if response.respond_to?(:id) && response.id
                metadata["created"] = response.created if response.respond_to?(:created) && response.created
                metadata["model"] = response.model if response.respond_to?(:model) && response.model
                metadata["system_fingerprint"] = response.system_fingerprint if response.respond_to?(:system_fingerprint) && response.system_fingerprint
                metadata["service_tier"] = response.service_tier if response.respond_to?(:service_tier) && response.service_tier
                Common.set_json_attr(span, "braintrust.metadata", metadata)
              end
            end
          end

          # Instrumentation for ChatCompletionStream (returned by stream())
          # Uses current_completion_snapshot for accumulated output
          module ChatCompletionStream
            def self.included(base)
              base.prepend(InstanceMethods) unless applied?(base)
            end

            def self.applied?(base)
              base.ancestors.include?(InstanceMethods)
            end

            module InstanceMethods
              def each(&block)
                ctx = Braintrust::Contrib::Context.from(self)
                return super unless ctx&.[](:tracer) && !ctx[:consumed]

                trace_consumption(ctx) { super(&block) }
              end

              def text
                ctx = Braintrust::Contrib::Context.from(self)
                return super unless ctx&.[](:tracer) && !ctx[:consumed]

                original_enum = super
                Enumerator.new do |y|
                  trace_consumption(ctx) do
                    original_enum.each { |t| y << t }
                  end
                end
              end

              private

              def trace_consumption(ctx)
                ctx[:consumed] = true

                tracer = ctx[:tracer]
                params = ctx[:params]
                metadata = ctx[:metadata]
                completions_instance = ctx[:completions_instance]
                start_time = Braintrust::Internal::Time.measure

                tracer.in_span("Chat Completion") do |span|
                  completions_instance.send(:set_input, span, params)
                  Common.set_json_attr(span, "braintrust.metadata", metadata)

                  yield

                  finalize_stream_span(span, start_time, metadata, completions_instance)
                end
              end

              def finalize_stream_span(span, start_time, metadata, completions_instance)
                time_to_first_token = Braintrust::Internal::Time.measure(start_time)

                begin
                  snapshot = current_completion_snapshot
                  return unless snapshot

                  # Set output from accumulated choices
                  if snapshot.choices&.any?
                    choices_array = snapshot.choices.map(&:to_h)
                    Common.set_json_attr(span, "braintrust.output_json", choices_array)
                  end

                  # Set metrics
                  metrics = {}
                  if snapshot.usage
                    metrics = Common.parse_usage_tokens(snapshot.usage)
                  end
                  metrics["time_to_first_token"] = time_to_first_token
                  Common.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?

                  # Update metadata with response fields
                  metadata["id"] = snapshot.id if snapshot.respond_to?(:id) && snapshot.id
                  metadata["created"] = snapshot.created if snapshot.respond_to?(:created) && snapshot.created
                  metadata["model"] = snapshot.model if snapshot.respond_to?(:model) && snapshot.model
                  metadata["system_fingerprint"] = snapshot.system_fingerprint if snapshot.respond_to?(:system_fingerprint) && snapshot.system_fingerprint
                  metadata["service_tier"] = snapshot.service_tier if snapshot.respond_to?(:service_tier) && snapshot.service_tier
                  Common.set_json_attr(span, "braintrust.metadata", metadata)
                rescue => e
                  Braintrust::Log.debug("Failed to get completion snapshot: #{e.message}")
                end
              end
            end
          end

          # Instrumentation for Internal::Stream (returned by stream_raw())
          # Aggregates chunks manually since Internal::Stream has no built-in accumulation
          module InternalStream
            def self.included(base)
              base.prepend(InstanceMethods) unless applied?(base)
            end

            def self.applied?(base)
              base.ancestors.include?(InstanceMethods)
            end

            module InstanceMethods
              def each(&block)
                ctx = Braintrust::Contrib::Context.from(self)
                # Only trace if context present and is for chat completions (not other endpoints)
                return super unless ctx&.[](:tracer) && !ctx[:consumed] && ctx[:stream_type] == :raw

                ctx[:consumed] = true

                tracer = ctx[:tracer]
                params = ctx[:params]
                metadata = ctx[:metadata]
                completions_instance = ctx[:completions_instance]
                aggregated_chunks = []
                start_time = Braintrust::Internal::Time.measure
                time_to_first_token = nil

                tracer.in_span("Chat Completion") do |span|
                  completions_instance.send(:set_input, span, params)
                  Common.set_json_attr(span, "braintrust.metadata", metadata)

                  super do |chunk|
                    time_to_first_token ||= Braintrust::Internal::Time.measure(start_time)
                    aggregated_chunks << chunk.to_h
                    block&.call(chunk)
                  end

                  finalize_stream_span(span, aggregated_chunks, time_to_first_token, metadata)
                end
              end

              private

              def finalize_stream_span(span, aggregated_chunks, time_to_first_token, metadata)
                return if aggregated_chunks.empty?

                aggregated_output = Common.aggregate_streaming_chunks(aggregated_chunks)
                Common.set_json_attr(span, "braintrust.output_json", aggregated_output[:choices])

                # Set metrics
                metrics = {}
                if aggregated_output[:usage]
                  metrics = Common.parse_usage_tokens(aggregated_output[:usage])
                end
                metrics["time_to_first_token"] = time_to_first_token
                Common.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?

                # Update metadata with response fields
                metadata["id"] = aggregated_output[:id] if aggregated_output[:id]
                metadata["created"] = aggregated_output[:created] if aggregated_output[:created]
                metadata["model"] = aggregated_output[:model] if aggregated_output[:model]
                metadata["system_fingerprint"] = aggregated_output[:system_fingerprint] if aggregated_output[:system_fingerprint]
                metadata["service_tier"] = aggregated_output[:service_tier] if aggregated_output[:service_tier]
                Common.set_json_attr(span, "braintrust.metadata", metadata)
              end
            end
          end
        end
      end
    end
  end
end
