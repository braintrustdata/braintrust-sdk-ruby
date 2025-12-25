# frozen_string_literal: true

module Braintrust
  module Contrib
    module RubyOpenAI
      module Instrumentation
        # Aggregation utilities for ruby-openai gem instrumentation.
        # These are specific to the ruby-openai gem's data structures (string keys, plain hashes).
        module Common
          # Aggregate streaming chunks into a single response structure.
          # Specific to ruby-openai gem which uses string keys and plain hashes.
          # @param chunks [Array<Hash>] array of chunk hashes from stream (string keys)
          # @return [Hash] aggregated response with choices, usage, etc. (string keys)
          def self.aggregate_streaming_chunks(chunks)
            return {} if chunks.empty?

            # Initialize aggregated structure
            aggregated = {
              "id" => nil,
              "created" => nil,
              "model" => nil,
              "system_fingerprint" => nil,
              "usage" => nil,
              "choices" => []
            }

            # Track aggregated content and tool_calls for each choice index
            choice_data = {}

            chunks.each do |chunk|
              # Capture top-level fields from any chunk that has them
              aggregated["id"] ||= chunk["id"]
              aggregated["created"] ||= chunk["created"]
              aggregated["model"] ||= chunk["model"]
              aggregated["system_fingerprint"] ||= chunk["system_fingerprint"]

              # Aggregate usage (usually only in last chunk if stream_options.include_usage is set)
              aggregated["usage"] = chunk["usage"] if chunk["usage"]

              # Process choices
              choices = chunk["choices"]
              next unless choices.is_a?(Array)

              choices.each do |choice|
                index = choice["index"] || 0
                choice_data[index] ||= {
                  "index" => index,
                  "role" => nil,
                  "content" => +"",
                  "tool_calls" => [],
                  "finish_reason" => nil
                }

                delta = choice["delta"] || {}

                # Aggregate role (set once from first delta that has it)
                choice_data[index]["role"] ||= delta["role"]

                # Aggregate content
                choice_data[index]["content"] << delta["content"] if delta["content"]

                # Aggregate tool_calls
                tool_calls = delta["tool_calls"]
                if tool_calls.is_a?(Array) && tool_calls.any?
                  tool_calls.each do |tool_call_delta|
                    tc_id = tool_call_delta["id"]
                    if tc_id && !tc_id.empty?
                      # New tool call
                      choice_data[index]["tool_calls"] << {
                        "id" => tc_id,
                        "type" => tool_call_delta["type"],
                        "function" => {
                          "name" => +(tool_call_delta.dig("function", "name") || ""),
                          "arguments" => +(tool_call_delta.dig("function", "arguments") || "")
                        }
                      }
                    elsif choice_data[index]["tool_calls"].any?
                      # Continuation - append arguments to last tool call
                      last_tool_call = choice_data[index]["tool_calls"].last
                      if tool_call_delta.dig("function", "arguments")
                        last_tool_call["function"]["arguments"] << tool_call_delta["function"]["arguments"]
                      end
                    end
                  end
                end

                # Capture finish_reason
                choice_data[index]["finish_reason"] = choice["finish_reason"] if choice["finish_reason"]
              end
            end

            # Build final choices array
            aggregated["choices"] = choice_data.values.sort_by { |c| c["index"] }.map do |choice|
              message = {
                "role" => choice["role"],
                "content" => choice["content"].empty? ? nil : choice["content"]
              }

              # Add tool_calls to message if any
              message["tool_calls"] = choice["tool_calls"] if choice["tool_calls"].any?

              {
                "index" => choice["index"],
                "message" => message,
                "finish_reason" => choice["finish_reason"]
              }
            end

            aggregated
          end

          # Aggregate responses streaming chunks into a single response structure.
          # Specific to ruby-openai gem which uses string keys and plain hashes.
          # @param chunks [Array<Hash>] array of chunk hashes from stream (string keys)
          # @return [Hash] aggregated response with output, usage, id (string keys)
          def self.aggregate_responses_chunks(chunks)
            return {} if chunks.empty?

            # Find the response.completed event which has the final response
            completed_chunk = chunks.find { |c| c["type"] == "response.completed" }

            if completed_chunk && completed_chunk["response"]
              response = completed_chunk["response"]
              return {
                "id" => response["id"],
                "output" => response["output"],
                "usage" => response["usage"]
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
