# frozen_string_literal: true

require "net/http"
require_relative "../internal/encoding"
require "uri"

module Braintrust
  module Trace
    # Attachment represents binary data (images, audio, PDFs, etc.) that can be logged
    # as part of traces in Braintrust. Attachments are stored securely and can be viewed
    # in the Braintrust UI.
    #
    # Attachments are particularly useful for multimodal AI applications, such as vision
    # models that process images.
    #
    # @example Create attachment from file
    #   att = Braintrust::Trace::Attachment.from_file("image/png", "./photo.png")
    #   data_url = att.to_data_url
    #   # => "data:image/png;base64,iVBORw0KGgo..."
    #
    # @example Create attachment from bytes
    #   att = Braintrust::Trace::Attachment.from_bytes("image/jpeg", image_bytes)
    #   message = att.to_message
    #   # => {"type" => "base64_attachment", "content" => "data:image/jpeg;base64,..."}
    #
    # @example Use in a trace span
    #   att = Braintrust::Trace::Attachment.from_file("image/png", "./photo.png")
    #   messages = [
    #     {
    #       role: "user",
    #       content: [
    #         {type: "text", text: "What's in this image?"},
    #         att.to_h  # Converts to {"type" => "base64_attachment", "content" => "..."}
    #       ]
    #     }
    #   ]
    #   span.set_attribute("braintrust.input_json", JSON.generate(messages))
    class Attachment
      # Common MIME type constants for convenience
      IMAGE_PNG = "image/png"
      IMAGE_JPEG = "image/jpeg"
      IMAGE_JPG = "image/jpg"
      IMAGE_GIF = "image/gif"
      IMAGE_WEBP = "image/webp"
      TEXT_PLAIN = "text/plain"
      APPLICATION_PDF = "application/pdf"

      # @!visibility private
      def initialize(content_type, data)
        @content_type = content_type
        @data = data
      end

      # Creates an attachment from raw bytes.
      #
      # @param content_type [String] MIME type of the data (e.g., "image/png")
      # @param data [String] Binary data as a string
      # @return [Attachment] New attachment instance
      #
      # @example
      #   image_data = File.binread("photo.png")
      #   att = Braintrust::Trace::Attachment.from_bytes("image/png", image_data)
      def self.from_bytes(content_type, data)
        new(content_type, data)
      end

      # Creates an attachment by reading from a file.
      #
      # @param content_type [String] MIME type of the file (e.g., "image/png")
      # @param path [String] Path to the file to read
      # @return [Attachment] New attachment instance
      # @raise [Errno::ENOENT] If the file does not exist
      #
      # @example
      #   att = Braintrust::Trace::Attachment.from_file("image/png", "./photo.png")
      def self.from_file(content_type, path)
        data = File.binread(path)
        new(content_type, data)
      end

      # Creates an attachment by fetching data from a URL.
      #
      # The content type is inferred from the Content-Type header in the HTTP response.
      # If the header is not present, it falls back to "application/octet-stream".
      #
      # @param url [String] URL to fetch
      # @return [Attachment] New attachment instance
      # @raise [StandardError] If the HTTP request fails
      #
      # @example
      #   att = Braintrust::Trace::Attachment.from_url("https://example.com/image.png")
      def self.from_url(url)
        uri = URI.parse(url)
        response = Net::HTTP.get_response(uri)

        unless response.is_a?(Net::HTTPSuccess)
          raise StandardError, "Failed to fetch URL: #{response.code} #{response.message}"
        end

        content_type = response.content_type || "application/octet-stream"
        new(content_type, response.body)
      end

      # Converts the attachment to a data URL format.
      #
      # @return [String] Data URL in the format "data:<content-type>;base64,<encoded-data>"
      #
      # @example
      #   att = Braintrust::Trace::Attachment.from_bytes("image/png", image_data)
      #   att.to_data_url
      #   # => "data:image/png;base64,iVBORw0KGgo..."
      def to_data_url
        encoded = Internal::Encoding::Base64.strict_encode64(@data)
        "data:#{@content_type};base64,#{encoded}"
      end

      # Converts the attachment to a message format suitable for LLM APIs.
      #
      # @return [Hash] Message hash with "type" and "content" keys
      #
      # @example
      #   att = Braintrust::Trace::Attachment.from_bytes("image/png", image_data)
      #   att.to_message
      #   # => {"type" => "base64_attachment", "content" => "data:image/png;base64,..."}
      def to_message
        {
          "type" => "base64_attachment",
          "content" => to_data_url
        }
      end

      # Alias for {#to_message}. Converts the attachment to a hash representation.
      #
      # @return [Hash] Same as {#to_message}
      alias_method :to_h, :to_message
    end
  end
end
