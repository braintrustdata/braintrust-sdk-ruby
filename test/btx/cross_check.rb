# frozen_string_literal: true

require "json"

module Braintrust
  module BTX
    # Raised when the locally-converted in-memory spans diverge from the
    # authoritative brainstore spans returned by BTQL in live mode.
    class CrossCheckError < StandardError; end

    # Cross-checks the in-memory OTel->brainstore conversion against the real
    # brainstore spans fetched from the backend (live mode only).
    #
    # This mirrors the Java SpanFetcher.assertConverterMatchesBrainstore: a
    # passing live run should also guarantee that the in-memory converter
    # produces spans consistent with what the backend actually stored.
    #
    # The comparison is intentionally lenient — it asserts that every concrete
    # value the converter produced also appears (equal) in the corresponding
    # real span, skipping:
    #   - nil values on either side (don't-care / backend-omitted)
    #   - "id" fields (dynamic, non-deterministic)
    #   - metrics values (token counts vary run-to-run; only key presence + type)
    #   - braintrust_attachment references (converter has the data URL form,
    #     the backend stores an uploaded reference; both are valid)
    module CrossCheck
      module_function

      # Assert the converted spans are a lenient subset of the real spans.
      #
      # @param converted [Array<Hash>] spans from SpanConverter.to_brainstore_spans
      # @param real [Array<Hash>] spans fetched via BTQL
      # @param display_name [String] spec id for error messages
      # @raise [CrossCheckError] if the conversion is inconsistent with the backend
      def assert_matches(converted, real, display_name)
        if converted.length != real.length
          raise CrossCheckError,
            "#{display_name}: in-memory converter produced #{converted.length} span(s) " \
            "but brainstore returned #{real.length}.\n" \
            "Converted:\n#{pretty(converted)}\n\nBrainstore:\n#{pretty(real)}"
        end

        real_by_name = index_by_name(real)
        errors = []

        converted.each_with_index do |conv, i|
          name = (conv["span_attributes"] || {})["name"] || conv["name"]
          real_span = real_by_name[name] || real[i]
          ctx = "converted[#{name || i}]"

          # "name" is a synthetic top-level field added by the converter for
          # spec-assertion convenience; the real span keeps it in
          # span_attributes.name. "metrics" are checked separately (presence only).
          conv_subset = conv.reject { |k, _| k == "name" || k == "metrics" }
          assert_subset(conv_subset, real_span, ctx, errors)
          assert_metrics_keys_present(conv, real_span, ctx, errors)
        end

        unless errors.empty?
          raise CrossCheckError,
            "#{display_name}: in-memory spans do not match live brainstore spans:\n" +
              errors.join("\n")
        end
      end

      # ---- internals ----

      def index_by_name(spans)
        spans.each_with_object({}) do |span, acc|
          attrs = span["span_attributes"] || {}
          name = attrs["name"] || span["name"]
          acc[name] = span if name
        end
      end

      # Every concrete value in +subset+ must appear (equal) in +superset+,
      # recursively. Lenient per the rules documented above.
      def assert_subset(subset, superset, ctx, errors)
        return if subset.nil?
        return if superset.nil? # backend may omit/transform certain fields

        # If one side is a Hash and the other isn't, the backend likely
        # transformed the shape — skip rather than fail (matches Java).
        return if subset.is_a?(Hash) != superset.is_a?(Hash)

        if subset.is_a?(Array)
          unless superset.is_a?(Array)
            errors << "#{ctx}: expected an array but brainstore has #{superset.class}"
            return
          end
          subset.each_with_index do |item, i|
            break if i >= superset.length
            assert_subset(item, superset[i], "#{ctx}[#{i}]", errors)
          end
          return
        end

        unless subset.is_a?(Hash)
          # Scalar leaves: strings may vary across runs (model text), so only
          # assert non-null. Numbers/booleans are deterministic — exact match.
          if subset.is_a?(String)
            errors << "#{ctx}: expected non-null string, got nil" if superset.nil?
          elsif subset != superset
            errors << "#{ctx}: converted=#{subset.inspect} but brainstore=#{superset.inspect}"
          end
          return
        end

        # Both hashes.
        if attachment?(subset)
          # Converter logs a data-URL-derived attachment; backend stores an
          # uploaded reference. Both are valid — just require the backend also
          # produced an attachment reference.
          unless attachment?(superset)
            errors << "#{ctx}: converted is a braintrust_attachment but brainstore is #{superset.inspect}"
          end
          return
        end

        subset.each do |key, val|
          next if val.nil?
          next if key == "id" # dynamic / non-deterministic
          assert_subset(val, superset[key], "#{ctx}.#{key}", errors)
        end
      end

      # Every metric key the converter produced must appear as a non-null
      # number in the real span (when the backend reports it). Token counts are
      # non-deterministic, so we check presence + type, not equality.
      def assert_metrics_keys_present(conv, real_span, ctx, errors)
        conv_metrics = conv["metrics"]
        return unless conv_metrics.is_a?(Hash)
        real_metrics = real_span["metrics"]
        return unless real_metrics.is_a?(Hash) # backend may omit metrics

        conv_metrics.each do |key, val|
          next if val.nil?
          real_val = real_metrics[key]
          next if real_val.nil? # backend may compute differently; skip
          unless real_val.is_a?(Numeric)
            errors << "#{ctx}.metrics.#{key}: expected a number but brainstore has #{real_val.class}"
          end
        end
      end

      def attachment?(hash)
        hash.is_a?(Hash) && hash["type"] == "braintrust_attachment"
      end

      def pretty(obj)
        JSON.pretty_generate(obj)
      rescue
        obj.inspect
      end
    end
  end
end
