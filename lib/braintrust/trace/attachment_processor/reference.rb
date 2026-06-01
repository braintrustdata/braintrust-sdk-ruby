# frozen_string_literal: true

require "securerandom"

module Braintrust
  module Trace
    module AttachmentProcessor
      # Reference is the JSON-serializable object that replaces inline base64
      # attachment data on a span. Its shape is the cross-SDK Braintrust
      # attachment reference format understood by the Braintrust collector and
      # UI.
      #
      # @example
      #   ref = Reference.new("image/png")
      #   ref.to_h
      #   # => {"type"=>"braintrust_attachment", "content_type"=>"image/png",
      #   #     "filename"=>"attachment.png", "key"=>"<uuid>"}
      class Reference
        TYPE = "braintrust_attachment"

        # MIME type to file extension mapping. Used to derive the filename.
        CONTENT_TYPE_EXTENSIONS = {
          "image/png" => ".png",
          "image/jpeg" => ".jpg",
          "image/jpg" => ".jpg",
          "image/gif" => ".gif",
          "image/webp" => ".webp",
          "image/svg+xml" => ".svg",
          "application/pdf" => ".pdf",
          "text/plain" => ".txt",
          "text/csv" => ".csv",
          "text/html" => ".html",
          "text/markdown" => ".md",
          "application/json" => ".json",
          "application/msword" => ".doc",
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => ".docx",
          "application/vnd.ms-excel" => ".xls",
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => ".xlsx",
          "video/mp4" => ".mp4",
          "video/webm" => ".webm",
          "video/quicktime" => ".mov",
          "audio/mpeg" => ".mp3",
          "audio/mp3" => ".mp3",
          "audio/wav" => ".wav"
        }.freeze

        attr_reader :type, :content_type, :filename, :key

        # @param content_type [String] MIME type (e.g. "image/png")
        # @param key [String, nil] Storage key; a fresh UUID is generated when omitted
        def initialize(content_type, key: nil)
          @type = TYPE
          @content_type = content_type
          @filename = "attachment#{self.class.content_type_to_extension(content_type)}"
          @key = key || SecureRandom.uuid
        end

        # @return [Hash] the JSON-embeddable reference object
        def to_h
          {
            "type" => @type,
            "content_type" => @content_type,
            "filename" => @filename,
            "key" => @key
          }
        end

        # Map a MIME type to a file extension (leading dot included).
        #
        # Falls back to the MIME subtype (stripped of parameters/suffixes) when
        # the type is unknown, or an empty string when there is no subtype.
        #
        # @param content_type [String]
        # @return [String]
        def self.content_type_to_extension(content_type)
          known = CONTENT_TYPE_EXTENSIONS[content_type.to_s.downcase]
          return known if known

          parts = content_type.to_s.split("/", 2)
          return "" unless parts.length == 2

          sub = parts[1]
          idx = sub.index(/[;-]/)
          sub = sub[0...idx] if idx
          sub.empty? ? "" : ".#{sub}"
        end
      end
    end
  end
end
