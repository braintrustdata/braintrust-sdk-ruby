# frozen_string_literal: true

require "opentelemetry/sdk"
require "json"

require_relative "common"
require_relative "../../support/otel"

module Braintrust
  module Contrib
    module LlmRb
      module Instrumentation
        # Context instrumentation for llm.rb.
        # Wraps LLM::Context#talk to create Braintrust spans for chat completions.
        module Context
          def self.included(base)
            base.prepend(InstanceMethods) unless applied?(base)
          end

          def self.applied?(base)
            base.ancestors.include?(InstanceMethods)
          end

          module InstanceMethods
            # Wrap talk() to trace chat completions.
            # Captures input messages, output, token usage, and timing.
            # NOTE: super must be called from within this method (not a helper)
            # because Ruby's super keyword resolves the method chain at the call site.
            def talk(prompt, params = {})
              return super unless tracing_enabled?

              tracer = Braintrust::Contrib.tracer_for(self)

              tracer.in_span("llm_rb.chat") do |span|
                # Capture inputs BEFORE calling super (before @messages is updated)
                input_messages = build_input_messages(prompt, params)
                Support::OTel.set_json_attr(span, "braintrust.input_json", input_messages) if input_messages.any?

                metadata = extract_metadata(params)

                begin
                  res = super(prompt, params)

                  # Capture output from response
                  output = capture_output(res)
                  Support::OTel.set_json_attr(span, "braintrust.output_json", output) unless output.empty?

                  # Update metadata with actual model from response
                  if res.respond_to?(:model) && res.model
                    metadata["model"] = res.model
                  end
                  Support::OTel.set_json_attr(span, "braintrust.metadata", metadata)

                  # Capture token metrics
                  usage = res.respond_to?(:usage) ? res.usage : nil
                  metrics = Common.parse_usage_tokens(usage)
                  Support::OTel.set_json_attr(span, "braintrust.metrics", metrics) unless metrics.empty?

                  res
                rescue => e
                  span.record_exception(e)
                  span.status = ::OpenTelemetry::Trace::Status.error("llm.rb error: #{e.message}")
                  raise
                end
              end
            end

            private

            # Checks if tracing is enabled via Braintrust::Contrib context.
            def tracing_enabled?
              ctx = Braintrust::Contrib.context_for(self)
              ctx&.[](:enabled) != false
            end

            # Build input messages array from existing history + new prompt.
            # Called BEFORE super so we capture the state before @messages is updated.
            def build_input_messages(prompt, params)
              existing = @messages.to_a.map { |m| format_message_for_input(m) }

              new_msgs = if defined?(::LLM::Prompt) && ::LLM::Prompt === prompt
                prompt.to_a.map { |m| format_message_for_input(m) }
              elsif prompt.is_a?(Array)
                prompt.flat_map do |m|
                  if m.respond_to?(:role)
                    [format_message_for_input(m)]
                  else
                    [{"role" => "user", "content" => m.to_s}]
                  end
                end
              else
                role = (params[:role] || @params[:role] || @llm.user_role).to_s
                [{"role" => role, "content" => prompt.to_s}]
              end

              existing + new_msgs
            end

            # Format an LLM::Message into OpenAI-compatible hash.
            def format_message_for_input(msg)
              return {"role" => "user", "content" => msg.to_s} unless msg.respond_to?(:role)

              formatted = {"role" => msg.role.to_s}

              content = msg.content
              content = content.to_s if content && !content.is_a?(String)
              formatted["content"] = content

              # Tool calls on assistant messages
              if msg.respond_to?(:extra) && (tcs = msg.extra&.tool_calls)&.respond_to?(:any?) && tcs.any?
                formatted["tool_calls"] = tcs.map { |tc| format_tool_call_for_input(tc) }
                formatted["content"] = nil
              end

              formatted.compact
            end

            # Format a tool call into OpenAI-compatible format.
            def format_tool_call_for_input(tc)
              id = tc.respond_to?(:[]) ? (tc["id"] || tc[:id]) : nil
              name = tc.respond_to?(:[]) ? (tc["name"] || tc[:name]) : nil
              args = tc.respond_to?(:[]) ? (tc["arguments"] || tc[:arguments]) : nil
              args_str = args.is_a?(String) ? args : args.to_json

              {
                "id" => id,
                "type" => "function",
                "function" => {
                  "name" => name,
                  "arguments" => args_str
                }
              }.compact
            end

            # Extract metadata from the context (provider name, model).
            def extract_metadata(params)
              provider_name = @llm.respond_to?(:name) ? @llm.name.to_s : @llm.class.name.split("::").last.downcase
              merged = @params.merge(params)
              model = merged[:model]

              {
                "provider" => "llm_rb",
                "llm_provider" => provider_name,
                "model" => model
              }.compact
            end

            # Capture output messages from the response.
            def capture_output(res)
              return [] unless res.respond_to?(:choices)

              res.choices.map { |msg| format_message_for_input(msg) }
            rescue
              []
            end
          end
        end
      end
    end
  end
end
