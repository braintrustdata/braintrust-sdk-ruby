# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"
require_relative "../../support/otel"
require_relative "../../support/anthropic"

module Braintrust
  module Contrib
    module Anthropic
      module Instrumentation
        # Messages instrumentation for Anthropic.
        # Wraps create() and stream() methods to create spans.
        module Messages
          def self.included(base)
            base.prepend(InstanceMethods) unless applied?(base)
          end

          def self.applied?(base)
            base.ancestors.include?(InstanceMethods)
          end

          module InstanceMethods
            METADATA_FIELDS = %i[
              model max_tokens temperature top_p top_k stop_sequences
              stream tools tool_choice thinking metadata service_tier
            ].freeze

            # Wrap synchronous messages.create
            def create(**params)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)

              tracer.in_span("anthropic.messages.create") do |span|
                metadata = build_metadata(params)
                set_input(span, params)

                response = super(**params)

                set_output(span, response)
                set_metrics(span, response)
                finalize_metadata(span, metadata, response)

                response
              end
            end

            # Wrap streaming messages.stream
            # Creates span for HTTP request; second span created in MessageStream#each
            def stream(**params)
              client = instance_variable_get(:@client)
              tracer = Braintrust::Contrib.tracer_for(client)
              metadata = build_metadata(params, stream: true)

              tracer.in_span("anthropic.messages.stream") do |span|
                set_input(span, params)
                Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)

                stream_obj = super
                Braintrust::Contrib::Context.set!(stream_obj,
                  tracer: tracer,
                  params: params,
                  metadata: metadata,
                  messages_instance: self)
                stream_obj
              rescue => e
                span.record_exception(e)
                span.status = ::OpenTelemetry::Trace::Status.error("Anthropic API error: #{e.message}")
                raise
              end
            end

            private

            def finalize_stream_span(span, stream_obj, metadata)
              if stream_obj.respond_to?(:accumulated_message)
                begin
                  msg = stream_obj.accumulated_message
                  set_output(span, msg)
                  set_metrics(span, msg)
                  metadata["stop_reason"] = msg.stop_reason if msg.respond_to?(:stop_reason) && msg.stop_reason
                  metadata["model"] = msg.model if msg.respond_to?(:model) && msg.model
                rescue => e
                  Braintrust::Log.debug("Failed to get accumulated message: #{e.message}")
                end
              end
              Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)
            end

            def build_metadata(params, stream: false)
              metadata = {
                "provider" => "anthropic",
                "endpoint" => "/v1/messages"
              }
              metadata["stream"] = true if stream
              METADATA_FIELDS.each do |field|
                metadata[field.to_s] = params[field] if params.key?(field)
              end
              metadata
            end

            def set_input(span, params)
              input_messages = []

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
                messages_array = params[:messages].map(&:to_h)
                input_messages.concat(messages_array)
              end

              Support::OTel.set_json_attr(span, "braintrust.input_json", input_messages) if input_messages.any?
            end

            def set_output(span, response)
              return unless response.respond_to?(:content) && response.content

              content_array = response.content.map(&:to_h)
              output = [{
                role: response.respond_to?(:role) ? response.role : "assistant",
                content: content_array
              }]
              Support::OTel.set_json_attr(span, "braintrust.output_json", output)
            end

            def set_metrics(span, response)
              return unless response.respond_to?(:usage) && response.usage

              metrics = Support::Anthropic.parse_usage_tokens(response.usage)
              Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?
            end

            def finalize_metadata(span, metadata, response)
              metadata["stop_reason"] = response.stop_reason if response.respond_to?(:stop_reason) && response.stop_reason
              metadata["stop_sequence"] = response.stop_sequence if response.respond_to?(:stop_sequence) && response.stop_sequence
              metadata["model"] = response.model if response.respond_to?(:model) && response.model
              Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)
            end
          end
        end

        # MessageStream instrumentation for Anthropic.
        # Prepended to Anthropic::Helpers::Streaming::MessageStream to create spans on consumption.
        module MessageStream
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

            def close
              ctx = Braintrust::Contrib::Context.from(self)
              if ctx&.[](:tracer) && !ctx[:consumed]
                # Stream closed without consumption - create minimal span
                ctx[:consumed] = true
                tracer = ctx[:tracer]
                params = ctx[:params]
                metadata = ctx[:metadata]
                messages_instance = ctx[:messages_instance]

                tracer.in_span("anthropic.messages.create") do |span|
                  messages_instance.send(:set_input, span, params)
                  Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)
                end
              end
              super
            end

            private

            def trace_consumption(ctx)
              # Mark as consumed to prevent re-entry (accumulated_message calls each internally)
              ctx[:consumed] = true

              tracer = ctx[:tracer]
              params = ctx[:params]
              metadata = ctx[:metadata]
              messages_instance = ctx[:messages_instance]

              tracer.in_span("anthropic.messages.create") do |span|
                messages_instance.send(:set_input, span, params)
                Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)

                yield

                messages_instance.send(:finalize_stream_span, span, self, metadata)
              end
            end
          end
        end
      end
    end
  end
end
