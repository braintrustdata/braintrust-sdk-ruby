# frozen_string_literal: true

require "test_helper"
require "json"
require "braintrust/trace/attachment_processor/processor"

module Braintrust
  module Trace
    module AttachmentProcessor
      class ProcessorTest < Minitest::Test
        BASE64_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

        # Uploader that rejects every enqueue.
        class RejectingUploader < NoopUploader
          def enqueue(_ref, _data)
            false
          end
        end

        # Uploader that accepts the first N enqueues, then rejects.
        class LimitedUploader < NoopUploader
          def initialize(remaining)
            super()
            @remaining = remaining
          end

          def enqueue(_ref, _data)
            return false if @remaining <= 0

            @remaining -= 1
            true
          end
        end

        def processor(uploader = NoopUploader.new)
          Processor.new(uploader: uploader)
        end

        def openai_image_json
          JSON.generate([{"role" => "user", "content" => [
            {"type" => "image_url", "image_url" => {"url" => "data:image/png;base64,#{BASE64_PNG}"}}
          ]}])
        end

        def test_non_attachment_input_unchanged
          input = JSON.generate([{"role" => "user", "content" => "Hello, how are you?"}])
          assert_equal input, processor.process_and_upload(input)
        end

        def test_partial_data_uri_in_text_not_replaced
          input = JSON.generate([{"role" => "user",
                                  "content" => "Check this: data:image/png;base64,#{BASE64_PNG} please"}])
          assert_equal input, processor.process_and_upload(input)
        end

        def test_short_base64_not_replaced
          input = JSON.generate([{"role" => "user", "content" => [
            {"type" => "image", "source" => {"type" => "base64", "media_type" => "image/png", "data" => "abc123"}}
          ]}])
          assert_equal input, processor.process_and_upload(input)
        end

        def test_empty_input_returns_empty
          assert_equal "", processor.process_and_upload("")
          assert_nil processor.process_and_upload(nil)
        end

        def test_heuristic_skips_plain_text
          input = JSON.generate({"messages" => [{"role" => "user", "content" => "just text"}]})
          assert_equal input, processor.process_and_upload(input)
        end

        def test_malformed_json_does_not_kill_processor
          uploader = NoopUploader.new
          p = processor(uploader)

          # Passes the heuristic but fails to parse.
          bad = %({"data":"#{BASE64_PNG}" INVALID)
          assert_equal bad, p.process_and_upload(bad), "should return original on parse error"
          refute uploader.shutdown?, "uploader must not shut down on a parse error"

          # A subsequent valid span still gets processed.
          good = p.process_and_upload(openai_image_json)
          refute_equal openai_image_json, good
          assert_includes good, "braintrust_attachment"
        end

        def test_uploader_shutdown_skips_processing
          uploader = NoopUploader.new
          uploader.shutdown
          assert_equal openai_image_json, processor(uploader).process_and_upload(openai_image_json)
        end

        def test_rejecting_uploader_returns_original
          assert_equal openai_image_json, processor(RejectingUploader.new).process_and_upload(openai_image_json)
        end

        def test_partial_enqueue_failure_returns_original
          # Two attachments, limit of 1: the second enqueue fails mid-walk and
          # the whole rewrite must be abandoned (partial-replacement safety).
          input = JSON.generate([{"role" => "user", "content" => [
            {"type" => "image_url", "image_url" => {"url" => "data:image/png;base64,#{BASE64_PNG}"}},
            {"type" => "image_url", "image_url" => {"url" => "data:image/png;base64,#{BASE64_PNG}"}}
          ]}])
          assert_equal input, processor(LimitedUploader.new(1)).process_and_upload(input)
        end

        def test_multiple_attachments_all_replaced
          input = JSON.generate([{"role" => "user", "content" => [
            {"type" => "image_url", "image_url" => {"url" => "data:image/png;base64,#{BASE64_PNG}"}},
            {"type" => "image_url", "image_url" => {"url" => "data:image/png;base64,#{BASE64_PNG}"}}
          ]}])
          result = processor.process_and_upload(input)
          parsed = JSON.parse(result)
          content = parsed[0]["content"]
          assert_equal "braintrust_attachment", content[0]["image_url"]["url"]["type"]
          assert_equal "braintrust_attachment", content[1]["image_url"]["url"]["type"]
        end

        def test_deeply_nested_input_is_returned_unchanged
          # Build nesting deeper than MAX_WALK_DEPTH with an attachment at the
          # bottom; the walker must stop at the cap and leave it unchanged
          # (and must not exhaust the stack).
          node = {"type" => "image_url", "image_url" => {"url" => "data:image/png;base64,#{BASE64_PNG}"}}
          (Processor::MAX_WALK_DEPTH + 10).times { node = {"nested" => node} }
          input = JSON.generate(node, max_nesting: false)

          # Use a processor that parses with a generous nesting limit so we
          # exercise the walker's own depth cap rather than the JSON parser's.
          uploader = NoopUploader.new
          p = Processor.new(uploader: uploader, json_max_nesting: false)
          result = p.process_and_upload(input)
          assert_equal input, result
          refute uploader.shutdown?, "depth cap must not be treated as an upload failure"
        end

        def test_input_exceeding_json_parse_depth_is_skipped
          # Real input deeper than the JSON parser's default nesting limit is
          # treated as a per-span parse error and returned unchanged.
          node = {"type" => "image_url", "image_url" => {"url" => "data:image/png;base64,#{BASE64_PNG}"}}
          200.times { node = {"nested" => node} }
          input = JSON.generate(node, max_nesting: false)
          uploader = NoopUploader.new
          assert_equal input, processor(uploader).process_and_upload(input)
          refute uploader.shutdown?
        end

        def test_unrelated_fields_preserved
          input = JSON.generate([{"role" => "user", "extra" => "keep", "content" => [
            {"type" => "text", "text" => "hi"},
            {"type" => "image_url", "image_url" => {"url" => "data:image/png;base64,#{BASE64_PNG}"}}
          ]}])
          parsed = JSON.parse(processor.process_and_upload(input))
          assert_equal "keep", parsed[0]["extra"]
          assert_equal "hi", parsed[0]["content"][0]["text"]
        end
      end
    end
  end
end
