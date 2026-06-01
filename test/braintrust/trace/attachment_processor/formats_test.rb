# frozen_string_literal: true

require "test_helper"
require "json"
require "braintrust/trace/attachment_processor/formats"
require "braintrust/trace/attachment_processor/processor"

module Braintrust
  module Trace
    module AttachmentProcessor
      # Data-driven coverage of every vendor format. The TestAllFormatsHaveTestCases
      # test below fails if a format is added to Formats.all without a
      # corresponding test case here.
      class FormatsTest < Minitest::Test
        # 1x1 red PNG pixel, valid base64.
        BASE64_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
        # Single blank-page PDF, valid base64.
        BASE64_PDF = "JVBERi0xLjAKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCA2MTIgNzkyXSA+PgplbmRvYmoKeHJlZgowIDQKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDA5IDAwMDAwIG4gCjAwMDAwMDAwNTggMDAwMDAgbiAKMDAwMDAwMDExNSAwMDAwMCBuIAp0cmFpbGVyCjw8IC9TaXplIDQgL1Jvb3QgMSAwIFIgPj4Kc3RhcnR4cmVmCjE5MAolJUVPRgo="

        # Each entry: format name (must match Format#name), input JSON, and an
        # assertion block run against the parsed, processed result.
        CASES = [
          {
            name: "openai-image",
            format: "openai",
            input: {"role" => "user", "content" => [
              {"type" => "text", "text" => "describe"},
              {"type" => "image_url", "image_url" => {"url" => "data:image/png;base64,#{BASE64_PNG}"}}
            ]},
            assert: ->(t, root) {
              part = root["content"][1]
              t.assert_attachment_ref(part["image_url"]["url"], "image/png")
            }
          },
          {
            name: "openai-file",
            format: "openai",
            input: {"role" => "user", "content" => [
              {"type" => "file", "file" => {"filename" => "blank.pdf", "file_data" => "data:application/pdf;base64,#{BASE64_PDF}"}}
            ]},
            assert: ->(t, root) {
              file = root["content"][0]["file"]
              t.assert_equal "blank.pdf", file["filename"]
              t.assert_attachment_ref(file["file_data"], "application/pdf")
            }
          },
          {
            name: "bedrock-image",
            format: "bedrock",
            input: {"role" => "user", "content" => [
              {"image" => {"format" => "png", "source" => {"bytes" => BASE64_PNG}}}
            ]},
            assert: ->(t, root) {
              image = root["content"][0]["image"]
              t.assert_equal "png", image["format"]
              t.assert_attachment_ref(image["source"]["bytes"], "image/png")
            }
          },
          {
            name: "bedrock-document",
            format: "bedrock",
            input: {"role" => "user", "content" => [
              {"document" => {"format" => "pdf", "name" => "blank", "source" => {"bytes" => BASE64_PDF}}}
            ]},
            assert: ->(t, root) {
              doc = root["content"][0]["document"]
              t.assert_equal "pdf", doc["format"]
              t.assert_equal "blank", doc["name"]
              t.assert_attachment_ref(doc["source"]["bytes"], "application/pdf")
            }
          },
          {
            # Ambiguous "mp4" under an audio block must resolve to audio/mp4,
            # not video/mp4.
            name: "bedrock-audio-mp4",
            format: "bedrock",
            input: {"role" => "user", "content" => [
              {"audio" => {"format" => "mp4", "source" => {"bytes" => BASE64_PDF}}}
            ]},
            assert: ->(t, root) {
              audio = root["content"][0]["audio"]
              t.assert_equal "mp4", audio["format"]
              t.assert_attachment_ref(audio["source"]["bytes"], "audio/mp4")
            }
          },
          {
            name: "anthropic-image",
            format: "anthropic",
            input: {"role" => "user", "content" => [
              {"type" => "image", "source" => {"type" => "base64", "media_type" => "image/png", "data" => BASE64_PNG}}
            ]},
            assert: ->(t, root) {
              part = root["content"][0]
              t.assert_equal "image", part["type"]
              t.assert_attachment_ref(part["source"], "image/png")
            }
          },
          {
            name: "anthropic-document",
            format: "anthropic",
            input: {"role" => "user", "content" => [
              {"type" => "document", "source" => {"type" => "base64", "media_type" => "application/pdf", "data" => BASE64_PDF}}
            ]},
            assert: ->(t, root) {
              part = root["content"][0]
              t.assert_equal "document", part["type"]
              t.assert_attachment_ref(part["source"], "application/pdf")
            }
          },
          {
            name: "gemini-image",
            format: "gemini",
            input: {"contents" => [
              {"role" => "user", "parts" => [
                {"inlineData" => {"mimeType" => "image/png", "data" => BASE64_PNG}}
              ]}
            ]},
            assert: ->(t, root) {
              part = root["contents"][0]["parts"][0]
              t.assert_nil part["inlineData"], "inlineData should be removed"
              t.assert_attachment_ref(part["image_url"]["url"], "image/png")
            }
          },
          {
            name: "gemini-document",
            format: "gemini",
            input: {"contents" => [
              {"role" => "user", "parts" => [
                {"inlineData" => {"mimeType" => "application/pdf", "data" => BASE64_PDF}}
              ]}
            ]},
            assert: ->(t, root) {
              part = root["contents"][0]["parts"][0]
              t.assert_nil part["inlineData"], "inlineData should be removed"
              t.assert_nil part["image_url"], "non-image should not use image_url"
              t.assert_attachment_ref(part["file"]["file_data"], "application/pdf")
            }
          }
        ].freeze

        CASES.each do |tc|
          define_method("test_#{tc[:name].tr("-", "_")}") do
            input_json = JSON.generate(tc[:input])

            # The combined heuristic must match this format's test data.
            assert build_heuristic.match?(input_json),
              "heuristic should match test data for #{tc[:name]}"

            processor = Processor.new(uploader: NoopUploader.new)
            result = processor.process_and_upload(input_json)
            refute_equal input_json, result, "base64 should have been replaced for #{tc[:name]}"

            root = JSON.parse(result)
            instance_exec(self, root, &tc[:assert])
          end
        end

        # Ensures adding a new format without test data causes a failure.
        def test_all_formats_have_test_cases
          covered = CASES.map { |tc| tc[:format] }.uniq
          Formats.all.each do |fmt|
            assert_includes covered, fmt.name,
              "format #{fmt.name.inspect} has no test cases in CASES — add at least one"
          end
        end

        def test_entirely_data_uri
          assert Formats.entirely_data_uri?("data:image/png;base64,abc123")
          assert Formats.entirely_data_uri?(" data:image/png;base64,abc123 ")
          refute Formats.entirely_data_uri?("Check this: data:image/png;base64,abc123 please")
          refute Formats.entirely_data_uri?('"data:image/png;base64,abc123"')
          refute Formats.entirely_data_uri?('data:image/png;base64,abc\\n123')
          refute Formats.entirely_data_uri?("not-a-data-uri")
        end

        # Test assertion helper exposed to case blocks.
        def assert_attachment_ref(node, expected_content_type)
          assert node.is_a?(Hash), "attachment ref should be a Hash, got #{node.class}"
          assert_equal "braintrust_attachment", node["type"]
          assert_equal expected_content_type, node["content_type"]
          refute_empty node["filename"]
          refute_empty node["key"]
        end

        private

        def build_heuristic
          @build_heuristic ||= Formats.build_heuristic
        end
      end
    end
  end
end
