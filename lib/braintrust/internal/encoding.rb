# frozen_string_literal: true

module Braintrust
  module Internal
    # Encoding utilities using Ruby's native pack/unpack methods.
    # Avoids dependency on external gems that became bundled gems in Ruby 3.4.
    module Encoding
      # Base64 encoding/decoding using Ruby's native pack/unpack methods.
      # Drop-in replacement for the base64 gem's strict methods.
      #
      # @example Encode binary data
      #   Encoding::Base64.strict_encode64(image_bytes)
      #   # => "iVBORw0KGgo..."
      #
      # @example Decode base64 string
      #   Encoding::Base64.strict_decode64("iVBORw0KGgo...")
      #   # => "\x89PNG..."
      #
      module Base64
        module_function

        # Encodes binary data to base64 without newlines (strict encoding).
        #
        # @param data [String] Binary data to encode
        # @return [String] Base64-encoded string without newlines
        def strict_encode64(data)
          [data].pack("m0")
        end

        # Decodes a base64 string to binary data (strict decoding).
        #
        # @param str [String] Base64-encoded string
        # @return [String] Decoded binary data
        def strict_decode64(str)
          str.unpack1("m0")
        end
      end
    end
  end
end
