# frozen_string_literal: true

require "test_helper"
require "braintrust/trace/attachment_processor/reference"

module Braintrust
  module Trace
    module AttachmentProcessor
      class ReferenceTest < Minitest::Test
        def test_builds_braintrust_attachment_reference
          ref = Reference.new("image/png")

          assert_equal "braintrust_attachment", ref.type
          assert_equal "image/png", ref.content_type
          assert_equal "attachment.png", ref.filename
          refute_empty ref.key
        end

        def test_generates_unique_keys
          assert_match(/\A[0-9a-f-]{36}\z/, Reference.new("image/png").key)
          refute_equal Reference.new("image/png").key, Reference.new("image/png").key
        end

        def test_accepts_explicit_key
          ref = Reference.new("image/png", key: "fixed-key")
          assert_equal "fixed-key", ref.key
        end

        def test_to_h_shape
          ref = Reference.new("application/pdf", key: "k")
          assert_equal({
            "type" => "braintrust_attachment",
            "content_type" => "application/pdf",
            "filename" => "attachment.pdf",
            "key" => "k"
          }, ref.to_h)
        end

        def test_content_type_to_extension_known_types
          {
            "image/png" => ".png",
            "image/jpeg" => ".jpg",
            "application/pdf" => ".pdf",
            "video/mp4" => ".mp4",
            "audio/mpeg" => ".mp3",
            "audio/wav" => ".wav"
          }.each do |mime, ext|
            assert_equal ext, Reference.content_type_to_extension(mime), mime
          end
        end

        def test_content_type_to_extension_unknown_falls_back_to_subtype
          # Strips at the first "-" or ";" like the Go reference impl.
          assert_equal ".octet", Reference.content_type_to_extension("application/octet-stream")
        end

        def test_content_type_to_extension_strips_parameters
          assert_equal ".plain", Reference.content_type_to_extension("text/plain;charset=utf-8")
        end

        def test_content_type_to_extension_no_subtype
          assert_equal "", Reference.content_type_to_extension("weird")
        end

        def test_content_type_to_extension_is_case_insensitive
          assert_equal ".png", Reference.content_type_to_extension("IMAGE/PNG")
        end
      end
    end
  end
end
