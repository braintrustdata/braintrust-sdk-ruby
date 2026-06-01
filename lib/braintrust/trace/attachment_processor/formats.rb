# frozen_string_literal: true

require_relative "reference"
require_relative "../../internal/encoding"

module Braintrust
  module Trace
    module AttachmentProcessor
      # Vendor-specific base64 attachment formats.
      #
      # Each {Format} is a self-contained unit: a detection predicate plus a
      # replacement function. Adding support for a new vendor is a matter of
      # appending one entry to {Formats.all} — shared walk/upload logic does not
      # change.
      module Formats
        # Minimum length of a base64 string to consider it a real attachment.
        # Avoids false positives on short strings that happen to look base64-ish.
        MIN_BASE64_LEN = 20

        # Matches "data:<mime>;base64,".
        DATA_URI_PREFIX = 'data:([\w/\-.+]+);base64,'

        # Matches a base64 string of at least MIN_BASE64_LEN characters.
        BASE64_STR = "([A-Za-z0-9+/=]{#{MIN_BASE64_LEN},})"

        # Compiled pattern for parsing an entire data URI.
        DATA_URI_PATTERN = /#{DATA_URI_PREFIX}#{BASE64_STR}/

        # Heuristic fragment matching a quoted data URI (OpenAI format).
        DATA_URI_HEURISTIC = "\"#{DATA_URI_PREFIX}#{BASE64_STR}\""

        # Heuristic fragment matching "bytes"/"data" keys with a base64 value
        # (Bedrock/Anthropic/Gemini).
        BYTE_VALUE_HEURISTIC = "\"(?:bytes|data)\"\\s*:\\s*\"#{BASE64_STR}\""

        # A single vendor attachment format.
        #
        # @!attribute [r] name
        #   @return [String] human-readable label used for logging and test coverage tracking
        # @!attribute [r] heuristic_fragment
        #   @return [String] regex fragment contributed to the combined fast-path heuristic
        # @!attribute [r] match
        #   @return [Proc] +match.call(parent_key, node)+ -> Boolean
        # @!attribute [r] replace
        #   @return [Proc] +replace.call(node, upload_fn)+ -> [replacement, ok]
        Format = Struct.new(:name, :heuristic_fragment, :match, :replace, keyword_init: true)

        module_function

        # All supported vendor formats, checked in order during tree traversal.
        # @return [Array<Format>]
        def all
          @all ||= [openai, bedrock, anthropic, gemini]
        end

        # Build a single combined regex from every format's heuristic fragment.
        # Identical fragments are de-duplicated.
        #
        # @param formats [Array<Format>]
        # @return [Regexp]
        def build_heuristic(formats = all)
          fragments = formats.map(&:heuristic_fragment).uniq
          Regexp.new(fragments.join("|"))
        end

        # ── OpenAI ───────────────────────────────────────────────────────

        # Data URIs that appear as an entire text node value.
        # e.g. image_url.url = "data:image/png;base64,..."
        def openai
          Format.new(
            name: "openai",
            heuristic_fragment: DATA_URI_HEURISTIC,
            match: ->(_parent_key, node) {
              node.is_a?(String) && entirely_data_uri?(node) && DATA_URI_PATTERN.match?(node)
            },
            replace: ->(node, upload_fn) {
              m = DATA_URI_PATTERN.match(node)
              next [nil, false] unless m

              upload_and_create_ref(m[1], m[2], upload_fn)
            }
          )
        end

        # True when the trimmed value is entirely a data URI: starts with
        # "data:" and contains no quotes, backslashes, or spaces.
        def entirely_data_uri?(value)
          t = value.strip
          t.start_with?("data:") &&
            !t.include?('"') &&
            !t.include?("\\") &&
            !t.include?(" ")
        end

        # ── Bedrock (Converse API) ───────────────────────────────────────

        # Per-block-type format-to-MIME mappings. The same format string (e.g.
        # "mp4") resolves to different MIME types depending on the parent block
        # type (video/mp4 vs audio/mp4), so a single flat table is insufficient.
        CONVERSE_BLOCK_TYPE_FORMATS = {
          "image" => {
            "gif" => "image/gif",
            "jpeg" => "image/jpeg",
            "png" => "image/png",
            "webp" => "image/webp"
          },
          "video" => {
            "flv" => "video/x-flv",
            "mkv" => "video/x-matroska",
            "mov" => "video/quicktime",
            "mp4" => "video/mp4",
            "mpeg" => "video/mpeg",
            "mpg" => "video/mpeg",
            "three_gp" => "video/3gpp",
            "webm" => "video/webm",
            "wmv" => "video/x-ms-wmv"
          },
          "audio" => {
            "aac" => "audio/aac",
            "flac" => "audio/flac",
            "m4a" => "audio/mp4",
            "mka" => "audio/x-matroska",
            "mkv" => "audio/x-matroska",
            "mp3" => "audio/mpeg",
            "mp4" => "audio/mp4",
            "mpeg" => "audio/mpeg",
            "mpga" => "audio/mpeg",
            "ogg" => "audio/ogg",
            "opus" => "audio/opus",
            "pcm" => "audio/pcm",
            "wav" => "audio/wav",
            "webm" => "audio/webm",
            "x-aac" => "audio/aac"
          },
          "document" => {
            "csv" => "text/csv",
            "doc" => "application/msword",
            "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "html" => "text/html",
            "md" => "text/markdown",
            "pdf" => "application/pdf",
            "txt" => "text/plain",
            "xls" => "application/vnd.ms-excel",
            "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          }
        }.freeze

        # Bedrock wraps attachments in a parent block keyed by type
        # ("image"/"video"/"audio"/"document") containing
        # {"format": "<ext>", "source": {"bytes": "<base64>"}}.
        # The reference replaces source.bytes; surrounding fields are preserved.
        def bedrock
          Format.new(
            name: "bedrock",
            heuristic_fragment: BYTE_VALUE_HEURISTIC,
            match: ->(_parent_key, node) {
              node.is_a?(Hash) && !converse_block(node).nil?
            },
            replace: ->(node, upload_fn) {
              block = converse_block(node)
              next [nil, false] unless block

              block_key, inner, format_map = block
              fmt = inner["format"]
              content_type = format_map[fmt.to_s.downcase]
              next [nil, false] unless content_type

              source = inner["source"]
              b64 = source["bytes"]
              ref_val, ok = upload_and_create_ref(content_type, b64, upload_fn)
              next [nil, false] unless ok

              # Copy all fields, swapping source.bytes in the matched block.
              new_source = source.merge("bytes" => ref_val)
              new_inner = inner.merge("source" => new_source)
              [node.merge(block_key => new_inner), true]
            }
          )
        end

        # Returns [block_key, inner_hash, format_map] for the first recognized
        # Bedrock block in +obj+, or nil.
        def converse_block(obj)
          CONVERSE_BLOCK_TYPE_FORMATS.each do |block_key, format_map|
            inner = obj[block_key]
            next unless inner.is_a?(Hash)

            fmt = inner["format"]
            next unless fmt.is_a?(String)
            next unless format_map.key?(fmt.downcase)

            source = inner["source"]
            next unless source.is_a?(Hash)

            bytes = source["bytes"]
            next unless bytes.is_a?(String) && bytes.length >= MIN_BASE64_LEN

            return [block_key, inner, format_map]
          end
          nil
        end

        # ── Anthropic ────────────────────────────────────────────────────

        # {"type":"base64","media_type":"<mime>","data":"<base64>"} inside a
        # "source" object. The entire source object is replaced with the ref.
        def anthropic
          Format.new(
            name: "anthropic",
            heuristic_fragment: BYTE_VALUE_HEURISTIC,
            match: ->(_parent_key, node) {
              next false unless node.is_a?(Hash)
              next false unless node["type"] == "base64"

              media_type = node["media_type"]
              next false unless media_type.is_a?(String) && !media_type.empty?

              data = node["data"]
              data.is_a?(String) && data.length >= MIN_BASE64_LEN
            },
            replace: ->(node, upload_fn) {
              upload_and_create_ref(node["media_type"], node["data"], upload_fn)
            }
          )
        end

        # ── Gemini ───────────────────────────────────────────────────────

        # {"inlineData": {"mimeType":"<mime>","data":"<base64>"}}.
        # Images become image_url: {url: ref}; non-images become
        # file: {file_data: ref}.
        def gemini
          Format.new(
            name: "gemini",
            heuristic_fragment: BYTE_VALUE_HEURISTIC,
            match: ->(_parent_key, node) {
              next false unless node.is_a?(Hash)

              inline = node["inlineData"]
              next false unless inline.is_a?(Hash)

              mime = inline["mimeType"]
              next false unless mime.is_a?(String) && !mime.empty?

              data = inline["data"]
              data.is_a?(String) && data.length >= MIN_BASE64_LEN
            },
            replace: ->(node, upload_fn) {
              inline = node["inlineData"]
              content_type = inline["mimeType"]
              ref_val, ok = upload_and_create_ref(content_type, inline["data"], upload_fn)
              next [nil, false] unless ok

              wrapper = if content_type.start_with?("image/")
                {"image_url" => {"url" => ref_val}}
              else
                {"file" => {"file_data" => ref_val}}
              end

              # Copy all fields, swapping inlineData for the appropriate wrapper.
              result = {}
              node.each do |k, v|
                if k == "inlineData"
                  result.merge!(wrapper)
                else
                  result[k] = v
                end
              end
              [result, true]
            }
          )
        end

        # ── Shared helpers ───────────────────────────────────────────────

        # Decode base64 data, create a reference, and enqueue the upload.
        #
        # @return [Array(Hash, Boolean)] +[ref_hash, true]+ on success, or
        #   +[nil, false]+ when the data cannot be decoded or the upload was
        #   rejected.
        def upload_and_create_ref(content_type, b64_data, upload_fn)
          data = Internal::Encoding::Base64.strict_decode64(b64_data)
          ref = Reference.new(content_type)
          return [nil, false] unless upload_fn.call(ref, data)

          [ref.to_h, true]
        rescue ArgumentError
          # Invalid base64 — skip this value (per-span error).
          [nil, false]
        end
      end
    end
  end
end
