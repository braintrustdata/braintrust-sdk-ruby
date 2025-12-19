# frozen_string_literal: true

require "json"

require_relative "../../../trace/tokens"

module Braintrust
  module Contrib
    module OpenAI
      module Instrumentation
        # Chat completions instrumentation for OpenAI.
        # Provides modules that can be prepended to OpenAI::Client to instrument chat.completions API.
        module Common
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
          # @param usage [Hash, Object] usage object from OpenAI response
          # @return [Hash<String, Integer>] metrics hash with normalized names
          def self.parse_usage_tokens(usage)
            Braintrust::Trace.parse_openai_usage_tokens(usage)
          end

          # Aggregate streaming chunks into a single response structure
          # Follows the Go SDK logic for aggregating deltas
          # @param chunks [Array<Hash>] array of chunk hashes from stream
          # @return [Hash] aggregated response with choices, usage, etc.
          def self.aggregate_streaming_chunks(chunks)
            return {} if chunks.empty?

            # Initialize aggregated structure
            aggregated = {
              id: nil,
              created: nil,
              model: nil,
              system_fingerprint: nil,
              choices: [],
              usage: nil
            }

            # Track aggregated content and tool_calls for each choice index
            choice_data = {}

            chunks.each do |chunk|
              # Capture top-level fields from any chunk that has them
              aggregated[:id] ||= chunk[:id]
              aggregated[:created] ||= chunk[:created]
              aggregated[:model] ||= chunk[:model]
              aggregated[:system_fingerprint] ||= chunk[:system_fingerprint]

              # Aggregate usage (usually only in last chunk if stream_options.include_usage is set)
              if chunk[:usage]
                aggregated[:usage] = chunk[:usage]
              end

              # Process choices
              next unless chunk[:choices].is_a?(Array)
              chunk[:choices].each do |choice|
                index = choice[:index] || 0
                choice_data[index] ||= {
                  index: index,
                  role: nil,
                  content: +"",
                  tool_calls: [],
                  finish_reason: nil
                }

                delta = choice[:delta] || {}

                # Aggregate role (set once from first delta that has it)
                choice_data[index][:role] ||= delta[:role]

                # Aggregate content
                if delta[:content]
                  choice_data[index][:content] << delta[:content]
                end

                # Aggregate tool_calls (similar to Go SDK logic)
                if delta[:tool_calls].is_a?(Array) && delta[:tool_calls].any?
                  delta[:tool_calls].each do |tool_call_delta|
                    # Check if this is a new tool call or continuation
                    if tool_call_delta[:id] && !tool_call_delta[:id].empty?
                      # New tool call (dup strings to avoid mutating input)
                      choice_data[index][:tool_calls] << {
                        id: tool_call_delta[:id],
                        type: tool_call_delta[:type],
                        function: {
                          name: +(tool_call_delta.dig(:function, :name) || ""),
                          arguments: +(tool_call_delta.dig(:function, :arguments) || "")
                        }
                      }
                    elsif choice_data[index][:tool_calls].any?
                      # Continuation - append arguments to last tool call
                      last_tool_call = choice_data[index][:tool_calls].last
                      if tool_call_delta.dig(:function, :arguments)
                        last_tool_call[:function][:arguments] << tool_call_delta[:function][:arguments]
                      end
                    end
                  end
                end

                # Capture finish_reason
                if choice[:finish_reason]
                  choice_data[index][:finish_reason] = choice[:finish_reason]
                end
              end
            end

            # Build final choices array
            aggregated[:choices] = choice_data.values.sort_by { |c| c[:index] }.map do |choice|
              message = {
                role: choice[:role],
                content: choice[:content].empty? ? nil : choice[:content]
              }

              # Add tool_calls to message if any
              message[:tool_calls] = choice[:tool_calls] if choice[:tool_calls].any?

              {
                index: choice[:index],
                message: message,
                finish_reason: choice[:finish_reason]
              }
            end

            aggregated
          end

          # Aggregate responses streaming events into a single response structure
          # Follows similar logic to Python SDK's _postprocess_streaming_results
          # @param events [Array] array of event objects from stream
          # @return [Hash] aggregated response with output, usage, etc.
          def self.aggregate_responses_events(events)
            return {} if events.empty?

            # Find the response.completed event which has the final response
            completed_event = events.find { |e| e.respond_to?(:type) && e.type == :"response.completed" }

            if completed_event&.respond_to?(:response)
              response = completed_event.response
              # Convert the response object to a hash-like structure for logging
              return {
                id: response.respond_to?(:id) ? response.id : nil,
                output: response.respond_to?(:output) ? response.output : nil,
                usage: response.respond_to?(:usage) ? response.usage : nil
              }
            end

            # Fallback if no completed event found
            {}
          end
        end
      end
    end
  end
end
