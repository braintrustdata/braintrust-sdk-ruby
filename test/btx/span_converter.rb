# frozen_string_literal: true

require "json"
require "digest"

module Braintrust
  module BTX
    # Converts in-memory OTel SpanData spans into brainstore span format.
    #
    # Brainstore spans are the canonical representation used in Braintrust's
    # storage layer and returned by the BTQL API. The +expected_brainstore_spans+
    # in the YAML spec files are written against this format.
    #
    # The Braintrust SDK stores span payload in OTel span attributes as JSON
    # strings:
    #   braintrust.metrics         -> metrics
    #   braintrust.metadata        -> metadata
    #   braintrust.span_attributes -> span_attributes (with name injected from the OTel span name)
    #   braintrust.input_json      -> input
    #   braintrust.output_json     -> output
    #
    # Only LLM instrumentation spans (those carrying braintrust.span_attributes)
    # are converted; the root wrapper span created by the executor is excluded.
    #
    # This mirrors the Java SpanConverter so in-memory (VCR) validation matches
    # what the backend stores after ingestion.
    module SpanConverter
      module_function

      # Convert a list of exported OTel SpanData into brainstore-format hashes.
      #
      # @param otel_spans [Array<OpenTelemetry::SDK::Trace::SpanData>]
      # @param transform_attachments [Boolean] when true, replicate the backend's
      #   data-URI -> braintrust_attachment transform on the input. This is the
      #   behavior for live mode, where the SDK attachment processor is disabled
      #   and the backend performs the conversion after ingestion.
      #
      #   In replay mode the SDK attachment processor runs in-process and is
      #   expected to produce the references itself, so the converter must NOT
      #   re-transform — otherwise it would mask a broken/disabled processor and
      #   the attachment specs would pass even when the SDK did nothing.
      # @return [Array<Hash>] brainstore spans, in input order
      def to_brainstore_spans(otel_spans, transform_attachments: true)
        otel_spans
          .select { |span| llm_instrumentation_span?(span) }
          .map { |span| to_single_brainstore_span(span, transform_attachments: transform_attachments) }
      end

      def llm_instrumentation_span?(span)
        attrs = span.attributes || {}
        !attrs["braintrust.span_attributes"].nil?
      end

      def to_single_brainstore_span(span, transform_attachments: true)
        result = {}
        result["name"] = span.name
        result["metrics"] = parse_json_map(span, "braintrust.metrics")
        result["metadata"] = parse_json_map(span, "braintrust.metadata")
        input = parse_json_value(span, "braintrust.input_json")
        result["input"] = transform_attachments ? transform_input(input) : input
        result["output"] = parse_json_value(span, "braintrust.output_json")

        span_attrs = parse_json_map(span, "braintrust.span_attributes") || {}
        span_attrs = span_attrs.dup
        span_attrs["name"] = span.name
        result["span_attributes"] = span_attrs

        result
      end

      # Replicate the Braintrust backend's attachment transformation.
      #
      # OpenAI image_url.url: "data:mime;base64,..." -> {type: braintrust_attachment, ...}
      # OpenAI file.file_data: "data:mime;base64,..." -> {type: braintrust_attachment, ...}
      # Anthropic source: {type: base64, media_type, data} -> {type: braintrust_attachment, ...}
      def transform_input(input)
        case input
        when Array
          input.map { |item| transform_input_item(item) }
        when Hash
          # Google-style {contents: [...]}, not used by openai/anthropic but
          # handled for completeness.
          if input["contents"].is_a?(Array)
            dup = input.dup
            dup["contents"] = input["contents"].map { |item| transform_input_item(item) }
            dup
          else
            input
          end
        else
          input
        end
      end

      def transform_input_item(item)
        return item unless item.is_a?(Hash)

        msg = item.dup
        if msg["content"].is_a?(Array)
          msg["content"] = msg["content"].map { |part| transform_content_part(part) }
        end
        msg
      end

      def transform_content_part(part)
        return part unless part.is_a?(Hash)

        type = part["type"]

        # Anthropic: {type: image|document, source: {type: base64, media_type, data}}
        if (type == "image" || type == "document") && part["source"].is_a?(Hash)
          source = part["source"]
          if source["type"] == "base64"
            mime = source["media_type"] || "application/octet-stream"
            data = source["data"]
            if data
              new_part = part.dup
              new_part["source"] = to_attachment("data:#{mime};base64,#{data}")
              return new_part
            end
          end
          return part
        end

        # OpenAI image_url: {type: image_url, image_url: {url: "data:..."}}
        if type == "image_url" && part["image_url"].is_a?(Hash)
          image_url = part["image_url"]
          url = image_url["url"]
          if url.is_a?(String) && url.start_with?("data:")
            new_part = part.dup
            new_image_url = image_url.dup
            new_image_url["url"] = to_attachment(url)
            new_part["image_url"] = new_image_url
            return new_part
          end
          return part
        end

        # OpenAI file: {type: file, file: {filename, file_data: "data:..."}}
        if type == "file" && part["file"].is_a?(Hash)
          file = part["file"]
          file_data = file["file_data"]
          if file_data.is_a?(String) && file_data.start_with?("data:")
            new_part = part.dup
            new_file = file.dup
            new_file["file_data"] = to_attachment(file_data)
            new_part["file"] = new_file
            return new_part
          end
          return part
        end

        part
      end

      # Build a braintrust_attachment reference from a data URL.
      def to_attachment(data_url)
        content_type = "application/octet-stream"
        data = data_url
        if data_url.start_with?("data:")
          semicolon = data_url.index(";")
          comma = data_url.index(",")
          content_type = data_url[5...semicolon] if semicolon && semicolon > 5
          data = data_url[(comma + 1)..] if comma
        end
        ext = content_type.include?("/") ? content_type.split("/").last : "bin"
        key = "attachment-#{Digest::SHA256.hexdigest(data.to_s)[0, 12]}.#{ext}"
        {
          "type" => "braintrust_attachment",
          "content_type" => content_type,
          "filename" => key,
          "key" => key
        }
      end

      def parse_json_map(span, attr_key)
        value = parse_json_value(span, attr_key)
        value.is_a?(Hash) ? value : nil
      end

      def parse_json_value(span, attr_key)
        json = (span.attributes || {})[attr_key]
        return nil if json.nil?
        JSON.parse(json)
      rescue JSON::ParserError => e
        raise "Failed to parse #{attr_key} as JSON: #{json} (#{e.message})"
      end
    end
  end
end
