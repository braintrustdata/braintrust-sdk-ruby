# frozen_string_literal: true

module Braintrust
  module Contrib
    module OpenAI
      module Instrumentation
        # Aggregation utilities for official OpenAI SDK instrumentation.
        # These are specific to the official openai gem's data structures (symbol keys, SDK objects).
        module Common
          # Aggregate streaming chunks into a single response structure.
          # Specific to official OpenAI SDK which uses symbol keys and SDK objects.
          # @param chunks [Array<Hash>] array of chunk hashes from stream (symbol keys)
          # @return [Hash] aggregated response with choices, usage, etc. (symbol keys)
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
              aggregated[:usage] = chunk[:usage] if chunk[:usage]

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
                choice_data[index][:content] << delta[:content] if delta[:content]

                # Aggregate tool_calls
                if delta[:tool_calls].is_a?(Array) && delta[:tool_calls].any?
                  delta[:tool_calls].each do |tool_call_delta|
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
                choice_data[index][:finish_reason] = choice[:finish_reason] if choice[:finish_reason]
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

          # Aggregate responses streaming events into a single response structure.
          # Specific to official OpenAI SDK which returns typed event objects.
          # @param events [Array] array of event objects from stream
          # @return [Hash] aggregated response with output, usage, etc.
          def self.aggregate_responses_events(events)
            return {} if events.empty?

            # Find the response.completed event which has the final response
            completed_event = events.find { |e| e.respond_to?(:type) && e.type == :"response.completed" }

            if completed_event&.respond_to?(:response)
              response = completed_event.response
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
