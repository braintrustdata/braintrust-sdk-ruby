# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"
require_relative "../../support/otel"
require_relative "common"
require_relative "../../../internal/time"

module Braintrust
  module Contrib
    module Anthropic
      module Instrumentation
        # Beta Messages instrumentation for Anthropic.
        # Wraps client.beta.messages.create() and stream() methods to create spans.
        #
        # @note Beta APIs are experimental and subject to change between SDK versions.
        #   This module includes defensive coding to handle response format changes.
        module BetaMessages
          def self.included(base)
            base.prepend(InstanceMethods) unless applied?(base)
          end

          def self.applied?(base)
            base.ancestors.include?(InstanceMethods)
          end

          module InstanceMethods
            # Standard metadata fields (shared with stable API)
            METADATA_FIELDS = %i[
              model max_tokens temperature top_p top_k stop_sequences
              stream tools tool_choice thinking metadata service_tier
            ].freeze

            # Beta-specific metadata fields
            BETA_METADATA_FIELDS = %i[
              betas output_format
            ].freeze

            # Wrap synchronous beta.messages.create
            def create(**params)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)

              tracer.in_span("anthropic.messages.create") do |span|
                # Pre-call instrumentation (swallow errors)
                metadata = nil
                begin
                  metadata = build_metadata(params)
                  set_input(span, params)
                rescue => e
                  Braintrust::Log.debug("Beta API: Failed to capture request: #{e.message}")
                  metadata ||= {"provider" => "anthropic", "api_version" => "beta"}
                end

                # API call - let errors propagate naturally
                response = nil
                time_to_first_token = Braintrust::Internal::Time.measure do
                  response = super(**params)
                end

                # Post-call instrumentation (swallow errors)
                begin
                  set_output(span, response)
                  set_metrics(span, response, time_to_first_token)
                  finalize_metadata(span, metadata, response)
                rescue => e
                  Braintrust::Log.debug("Beta API: Failed to capture response: #{e.message}")
                end

                response
              end
            end

            # Wrap streaming beta.messages.stream
            # Stores context on stream object for span creation during consumption
            def stream(**params)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)

              # Pre-call instrumentation (swallow errors)
              metadata = nil
              begin
                metadata = build_metadata(params, stream: true)
              rescue => e
                Braintrust::Log.debug("Beta API: Failed to build stream metadata: #{e.message}")
                metadata = {"provider" => "anthropic", "api_version" => "beta", "stream" => true}
              end

              # API call - let errors propagate naturally
              stream_obj = super

              # Post-call instrumentation (swallow errors)
              begin
                Braintrust::Contrib::Context.set!(stream_obj,
                  tracer: tracer,
                  params: params,
                  metadata: metadata,
                  messages_instance: self,
                  start_time: Braintrust::Internal::Time.measure)
              rescue => e
                Braintrust::Log.debug("Beta API: Failed to set stream context: #{e.message}")
              end

              stream_obj
            end

            private

            def finalize_stream_span(span, stream_obj, metadata, time_to_first_token)
              if stream_obj.respond_to?(:accumulated_message)
                begin
                  msg = stream_obj.accumulated_message
                  set_output(span, msg)
                  set_metrics(span, msg, time_to_first_token)
                  metadata["stop_reason"] = msg.stop_reason if msg.respond_to?(:stop_reason) && msg.stop_reason
                  metadata["model"] = msg.model if msg.respond_to?(:model) && msg.model
                rescue => e
                  Braintrust::Log.debug("Beta API: Failed to get accumulated message: #{e.message}")
                end
              end
              Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)
            end

            def build_metadata(params, stream: false)
              metadata = {
                "provider" => "anthropic",
                "endpoint" => "/v1/messages",
                "api_version" => "beta"
              }
              metadata["stream"] = true if stream

              # Capture standard fields
              METADATA_FIELDS.each do |field|
                metadata[field.to_s] = params[field] if params.key?(field)
              end

              # Capture beta-specific fields with defensive handling
              capture_beta_fields(metadata, params)

              metadata
            rescue => e
              Braintrust::Log.debug("Beta API: Failed to build metadata: #{e.message}")
              {"provider" => "anthropic", "api_version" => "beta"}
            end

            def capture_beta_fields(metadata, params)
              # Capture betas array (e.g., ["structured-outputs-2025-11-13"])
              if params.key?(:betas)
                betas = params[:betas]
                metadata["betas"] = betas.is_a?(Array) ? betas : [betas]
              end

              # Capture output_format for structured outputs
              if params.key?(:output_format)
                output_format = params[:output_format]
                metadata["output_format"] = begin
                  if output_format.respond_to?(:to_h)
                    output_format.to_h
                  else
                    output_format
                  end
                rescue
                  output_format.to_s
                end
              end
            end

            def set_input(span, params)
              input_messages = []

              begin
                if params[:system]
                  system_content = params[:system]
                  if system_content.is_a?(Array)
                    system_text = system_content.map { |blk|
                      blk.is_a?(Hash) ? blk[:text] : blk
                    }.join("\n")
                    input_messages << {role: "system", content: system_text}
                  else
                    input_messages << {role: "system", content: system_content}
                  end
                end

                if params[:messages]
                  messages_array = params[:messages].map { |m| m.respond_to?(:to_h) ? m.to_h : m }
                  input_messages.concat(messages_array)
                end

                Support::OTel.set_json_attr(span, "braintrust.input_json", input_messages) if input_messages.any?
              rescue => e
                Braintrust::Log.debug("Beta API: Failed to capture input: #{e.message}")
              end
            end

            def set_output(span, response)
              return unless response

              begin
                return unless response.respond_to?(:content) && response.content

                content_array = response.content.map { |c| c.respond_to?(:to_h) ? c.to_h : c }
                output = [{
                  role: response.respond_to?(:role) ? response.role : "assistant",
                  content: content_array
                }]
                Support::OTel.set_json_attr(span, "braintrust.output_json", output)
              rescue => e
                Braintrust::Log.debug("Beta API: Failed to capture output: #{e.message}")
              end
            end

            def set_metrics(span, response, time_to_first_token)
              metrics = {}

              begin
                if response.respond_to?(:usage) && response.usage
                  metrics = Common.parse_usage_tokens(response.usage)
                end
                metrics["time_to_first_token"] = time_to_first_token if time_to_first_token
                Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
              rescue => e
                Braintrust::Log.debug("Beta API: Failed to capture metrics: #{e.message}")
              end
            end

            def finalize_metadata(span, metadata, response)
              begin
                metadata["stop_reason"] = response.stop_reason if response.respond_to?(:stop_reason) && response.stop_reason
                metadata["stop_sequence"] = response.stop_sequence if response.respond_to?(:stop_sequence) && response.stop_sequence
                metadata["model"] = response.model if response.respond_to?(:model) && response.model
              rescue => e
                Braintrust::Log.debug("Beta API: Failed to finalize metadata: #{e.message}")
              end

              Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)
            end
          end
        end
      end
    end
  end
end
