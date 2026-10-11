# frozen_string_literal: true

require "json"
require_relative "spec_loader"

module Braintrust
  module BTX
    # Raised when fetched/in-memory spans do not match the spec.
    class ValidationError < StandardError; end

    # Recursively validates brainstore spans against a spec's
    # expected_brainstore_spans. All failures are collected before raising so a
    # single run shows every mismatch.
    module SpanValidator
      module_function

      # ---- Named predicates (mirror is_* functions in the other SDKs) ----

      def non_negative_number?(value)
        value.is_a?(Numeric) && !value.is_a?(TrueClass) && !value.is_a?(FalseClass) && value >= 0
      end

      def positive_number?(value)
        value.is_a?(Numeric) && value > 0
      end

      def non_empty_string?(value)
        value.is_a?(String) && !value.empty?
      end

      def undefined_or_null?(value)
        value.nil?
      end

      # A list (possibly empty) of {type: summary_text, text: <non-empty>} hashes.
      def reasoning_message?(value)
        return false unless value.is_a?(Array)
        return true if value.empty?

        value.all? do |item|
          item.is_a?(Hash) &&
            item["type"] == "summary_text" &&
            item["text"].is_a?(String) && !item["text"].strip.empty?
        end
      end

      NAMED_MATCHERS = {
        "is_non_negative_number" => :non_negative_number?,
        "is_positive_number" => :positive_number?,
        "is_non_empty_string" => :non_empty_string?,
        "is_reasoning_message" => :reasoning_message?,
        "undefined_or_null" => :undefined_or_null?
      }.freeze

      # Resolve a FnMatcher to a callable taking the actual value.
      #
      # Named predicates dispatch to dedicated methods. Lambda expressions from
      # the spec are Python-style ("lambda value: ...") — since Ruby cannot eval
      # those, we translate the common case ("X in value") and otherwise fall
      # back to a non-null/non-empty check.
      def resolve_fn(matcher)
        expr = matcher.expr
        if NAMED_MATCHERS.key?(expr)
          meth = NAMED_MATCHERS[expr]
          return ->(v) { send(meth, v) }
        end

        # Python lambda like: lambda value: "Paris" in value
        if (m = expr.match(/\Alambda\s+\w+:\s*"(.+)"\s+in\s+\w+\z/))
          needle = m[1]
          return ->(v) { v.is_a?(String) && v.include?(needle) }
        end
        if (m = expr.match(/\Alambda\s+\w+:\s*'(.+)'\s+in\s+\w+\z/))
          needle = m[1]
          return ->(v) { v.is_a?(String) && v.include?(needle) }
        end

        # Unknown expression: loose "non-null and non-empty" check.
        ->(v) { !v.nil? && v != "" && v != [] && v != {} }
      end

      # ---- Public API ----

      # Validate +actual_spans+ against +spec.expected_brainstore_spans+.
      #
      # @param actual_spans [Array<Hash>] brainstore-format spans (string keys)
      # @param spec [LlmSpanSpec]
      # @raise [ValidationError] with every mismatch if validation fails
      def validate_spans(actual_spans, spec)
        expected_spans = spec.expected_brainstore_spans

        llm_spans = actual_spans.select do |s|
          attrs = s["span_attributes"] || {}
          attrs["type"] == "llm"
        end

        llm_spans = llm_spans.sort_by do |s|
          (s["span_attributes"] || {})["exec_counter"] || 0
        end

        if llm_spans.length < expected_spans.length
          raise ValidationError,
            "#{spec.display_name}: expected at least #{expected_spans.length} LLM span(s), " \
            "got #{llm_spans.length}.\nAll captured spans:\n#{pretty(actual_spans)}"
        end

        all_errors = []

        expected_spans.each_with_index do |expected_span, i|
          actual_span = llm_spans[i]
          span_errors = []
          expected_span.each do |key, exp_val|
            if actual_span.key?(key)
              validate_value(actual_span[key], exp_val, "span[#{i}].#{key}", span_errors)
            elsif optional?(exp_val)
              validate_value(nil, exp_val, "span[#{i}].#{key}", span_errors)
            else
              span_errors << "  span[#{i}].#{key}: key not found in actual span"
            end
          end

          unless span_errors.empty?
            name = (actual_span["span_attributes"] || {})["name"] || "?"
            all_errors << "\n--- Span #{i} (#{name}) ---\n" +
              span_errors.join("\n") +
              "\n\nFull span JSON:\n#{pretty(actual_span)}"
          end
        end

        unless all_errors.empty?
          raise ValidationError,
            "#{spec.display_name}: span validation failed:\n" + all_errors.join("\n")
        end
      end

      # Recursively validate +actual+ against +expected+, appending to +errors+.
      def validate_value(actual, expected, path, errors)
        case expected
        when OrMatcher
          validate_or(actual, expected, path, errors)
        when FnMatcher
          validate_fn(actual, expected, path, errors)
        when StartsWithMatcher
          unless actual.is_a?(String) && actual.start_with?(expected.prefix)
            errors << "#{path}: expected string starting with #{expected.prefix.inspect}, got #{actual.inspect}"
          end
        when GenMatcher
          # Generated values are placeholders; accept whatever is present.
          nil
        when nil
          # don't care
          nil
        when Hash
          validate_hash(actual, expected, path, errors)
        when Array
          validate_array(actual, expected, path, errors)
        else
          if actual != expected
            errors << "#{path}: expected=#{expected.inspect}, actual=#{actual.inspect}"
          end
        end
      end

      def validate_or(actual, expected, path, errors)
        or_errors = []
        matched = expected.alternatives.each_with_index.any? do |alt, i|
          alt_errors = []
          validate_value(actual, alt, path, alt_errors)
          if alt_errors.empty?
            true
          else
            or_errors << "  alternative[#{i}]: #{alt_errors.join("; ")}"
            false
          end
        end
        return if matched

        errors << "#{path}: none of #{expected.alternatives.length} OR alternatives matched:\n" +
          or_errors.join("\n")
      end

      def validate_fn(actual, expected, path, errors)
        fn = resolve_fn(expected)
        begin
          result = fn.call(actual)
        rescue => e
          errors << "#{path}: validator raised #{e.class}: #{e.message} (actual=#{actual.inspect})"
          return
        end
        unless result
          errors << "#{path}: validator #{expected.expr.inspect} returned false for actual=#{actual.inspect}"
        end
      end

      def validate_hash(actual, expected, path, errors)
        unless actual.is_a?(Hash)
          errors << "#{path}: expected hash, got #{actual.class} (#{actual.inspect})"
          return
        end
        expected.each do |key, exp_val|
          if actual.key?(key)
            validate_value(actual[key], exp_val, "#{path}.#{key}", errors)
          elsif optional?(exp_val)
            # An absent key is equivalent to a null value — validate accordingly
            # (e.g. !fn undefined_or_null is satisfied by a missing key).
            validate_value(nil, exp_val, "#{path}.#{key}", errors)
          else
            errors << "#{path}.#{key}: key not found in actual span"
          end
        end
      end

      # Whether a missing key is acceptable for this expected value: a literal
      # nil (don't-care) or a matcher that accepts nil.
      def optional?(expected)
        return true if expected.nil?
        expected.is_a?(FnMatcher) && resolve_fn(expected).call(nil)
      rescue
        false
      end

      def validate_array(actual, expected, path, errors)
        unless actual.is_a?(Array)
          # Single-item list vs object: when expected is a one-element list of a
          # hash and actual is a hash, validate actual against expected[0].
          if expected.length == 1 && expected[0].is_a?(Hash) && actual.is_a?(Hash)
            validate_value(actual, expected[0], "#{path}[0]", errors)
            return
          end
          errors << "#{path}: expected array, got #{actual.class} (#{actual.inspect})"
          return
        end
        if actual.length < expected.length
          errors << "#{path}: list too short — expected at least #{expected.length} elements, got #{actual.length}"
          return
        end
        expected.each_with_index do |exp_item, i|
          validate_value(actual[i], exp_item, "#{path}[#{i}]", errors)
        end
      end

      def pretty(obj)
        JSON.pretty_generate(obj)
      rescue
        obj.inspect
      end
    end
  end
end
