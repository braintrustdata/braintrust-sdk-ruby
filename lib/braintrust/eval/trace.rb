# frozen_string_literal: true

module Braintrust
  module Eval
    # Read-only trace data accessor for scorers.
    #
    # Per-case throwaway object — no global cache, no shared state.
    # Accepts lazy (lambda) or eager (Array) span sources.
    #
    # BTQL span shape (string keys from JSON):
    #   "span_attributes" => {"type" => "llm", "name" => "Chat Completion"}
    #   "input"  => [{"role" => "user", "content" => "..."}]        # flat message array
    #   "output" => [{"message" => {"role" => "assistant", ...}}]    # flat choices array
    #
    # @example Lazy loading from BTQL
    #   trace = Trace.new(spans: -> { btql.trace_spans(...) })
    #   trace.spans              # triggers BTQL query on first access
    #   trace.spans              # returns memoized result
    #
    # @example Eager loading
    #   trace = Trace.new(spans: [span1, span2])
    #   trace.spans              # returns array directly
    class Trace
      # @param spans [Proc, Array] Span source — a lambda (lazy) or Array (eager).
      def initialize(spans:)
        @spans_source = spans
        @spans_resolved = false
        @spans_memo = nil
      end

      # Resolve and return spans, optionally filtered by type.
      #
      # The type lives at span_attributes.type in BTQL rows (e.g. "llm", "eval", "task").
      #
      # @param span_type [String, nil] Filter to spans matching this type.
      #   Returns all spans when nil.
      # @return [Array<Hash>] Matching spans.
      def spans(span_type: nil)
        resolved = resolve_spans
        if span_type
          resolved.select { |s| span_type_for(s) == span_type }
        else
          resolved
        end
      end

      # Convenience method: extract a chronological message thread from LLM spans.
      #
      # Walks LLM spans, collects input messages (deduplicated) and output messages
      # (always included). Returns a flat chronological array.
      #
      # BTQL LLM span format:
      #   input:  flat array of messages  [{"role" => "user", "content" => "..."}]
      #   output: flat array of choices   [{"message" => {"role" => "assistant", ...}}]
      #
      # @return [Array<Hash>] Ordered message list.
      def thread
        llm_spans = spans(span_type: "llm")
        return [] if llm_spans.empty?

        seen = Set.new
        messages = []

        llm_spans.each do |span|
          # Input: flat message array or {messages: [...]} wrapper
          input = span["input"] || span[:input]
          input_messages = extract_input_messages(input)
          input_messages&.each do |msg|
            key = msg.hash
            unless seen.include?(key)
              seen.add(key)
              messages << msg
            end
          end

          # Output: flat choices array or {choices: [...]} wrapper
          output = span["output"] || span[:output]
          extract_output_messages(output)&.each do |msg|
            messages << msg
          end
        end

        messages
      end

      private

      # Extract the span type from a span hash.
      # Handles both string and symbol keys for span_attributes.type.
      def span_type_for(span)
        attrs = span["span_attributes"] || span[:span_attributes]
        return nil unless attrs
        attrs["type"] || attrs[:type]
      end

      # Extract input messages from a span's input field.
      # Handles both flat array format (BTQL) and {messages: [...]} wrapper.
      def extract_input_messages(input)
        return nil unless input
        return input if input.is_a?(Array)
        input["messages"] || input[:messages]
      end

      # Extract output messages from a span's output field.
      # Handles both flat choices array (BTQL) and {choices: [...]} wrapper.
      def extract_output_messages(output)
        return nil unless output
        choices = output.is_a?(Array) ? output : (output["choices"] || output[:choices])
        return nil unless choices
        choices.filter_map { |c| c["message"] || c[:message] }
      end

      def resolve_spans
        unless @spans_resolved
          @spans_memo = if @spans_source.respond_to?(:call)
            @spans_source.call
          else
            @spans_source
          end
          @spans_memo ||= []
          @spans_resolved = true
        end
        @spans_memo
      end
    end
  end
end
