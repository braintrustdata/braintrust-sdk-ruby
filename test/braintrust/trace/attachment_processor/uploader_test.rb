# frozen_string_literal: true

require "test_helper"
require "json"
require "braintrust/trace/attachment_processor/uploader"
require "braintrust/trace/attachment_processor/reference"

module Braintrust
  module Trace
    module AttachmentProcessor
      class UploaderTest < Minitest::Test
        API_URL = "https://api.test.local"
        SIGNED_URL = "https://storage.test.local/upload/abc"

        # Swallows log output so expected failure-path warnings don't pollute
        # test output.
        class SilentLogger
          def warn(*) = nil

          def debug(*) = nil

          def error(*) = nil

          def info(*) = nil
        end

        def setup
          @ref = Reference.new("image/png", key: "test-key")
          @data = "binary-png-bytes"
        end

        def build_uploader(**opts)
          S3Uploader.new(
            api_key: "test-api-key",
            api_url: API_URL,
            org_id: "org-123",
            initial_backoff: 0.01,
            shutdown_timeout: 5.0,
            logger: SilentLogger.new,
            **opts
          )
        end

        def stub_signed_url(headers: {})
          stub_request(:post, "#{API_URL}/attachment")
            .to_return(status: 200, body: JSON.generate({"signedUrl" => SIGNED_URL, "headers" => headers}))
        end

        def stub_upload(url: SIGNED_URL, status: 200)
          stub_request(:put, url).to_return(status: status)
        end

        def stub_status
          stub_request(:post, "#{API_URL}/attachment/status").to_return(status: 200, body: "{}")
        end

        def test_successful_upload_runs_full_three_step_flow
          stub_signed_url
          stub_upload
          stub_status

          uploader = build_uploader
          assert uploader.enqueue(@ref, @data)
          assert uploader.force_flush(5.0)

          refute uploader.shutdown?, "successful upload should not flag the uploader as failed"
          uploader.shutdown

          assert_requested(:post, "#{API_URL}/attachment")
          assert_requested(:put, SIGNED_URL)
          assert_requested(:post, "#{API_URL}/attachment/status")
        end

        def test_signed_url_request_sends_correct_payload
          stub_signed_url
          stub_upload
          stub_status

          uploader = build_uploader
          uploader.enqueue(@ref, @data)
          uploader.force_flush(5.0)
          uploader.shutdown

          assert_requested(:post, "#{API_URL}/attachment") do |req|
            body = JSON.parse(req.body)
            body["key"] == "test-key" &&
              body["filename"] == "attachment.png" &&
              body["content_type"] == "image/png" &&
              body["org_id"] == "org-123" &&
              req.headers["Authorization"] == "Bearer test-api-key"
          end
        end

        def test_upload_uses_content_type_and_signed_headers
          stub_signed_url(headers: {"x-custom" => "yes"})
          stub_upload
          stub_status

          uploader = build_uploader
          uploader.enqueue(@ref, @data)
          uploader.force_flush(5.0)
          uploader.shutdown

          assert_requested(:put, SIGNED_URL) do |req|
            req.headers["Content-Type"] == "image/png" &&
              req.headers["X-Custom"] == "yes" &&
              req.body == @data
          end
        end

        def test_azure_blob_adds_block_blob_header
          azure_url = "https://acct.blob.core.windows.net/c/blob"
          stub_request(:post, "#{API_URL}/attachment")
            .to_return(status: 200, body: JSON.generate({"signedUrl" => azure_url, "headers" => {}}))
          stub_upload(url: azure_url)
          stub_status

          uploader = build_uploader
          uploader.enqueue(@ref, @data)
          uploader.force_flush(5.0)
          uploader.shutdown

          assert_requested(:put, azure_url) { |req| req.headers["X-Ms-Blob-Type"] == "BlockBlob" }
        end

        def test_retries_on_5xx_then_succeeds
          stub_request(:post, "#{API_URL}/attachment")
            .to_return(status: 500).times(2).then
            .to_return(status: 200, body: JSON.generate({"signedUrl" => SIGNED_URL, "headers" => {}}))
          stub_upload
          stub_status

          uploader = build_uploader
          uploader.enqueue(@ref, @data)
          uploader.force_flush(5.0)

          refute uploader.shutdown?, "should recover after retries"
          uploader.shutdown
          assert_requested(:post, "#{API_URL}/attachment", times: 3)
        end

        def test_does_not_retry_4xx_and_fails
          stub_request(:post, "#{API_URL}/attachment").to_return(status: 400)
          stub_status

          uploader = build_uploader
          uploader.enqueue(@ref, @data)
          uploader.force_flush(5.0)

          assert uploader.shutdown?, "4xx on signed URL should fail the uploader"
          uploader.shutdown
          assert_requested(:post, "#{API_URL}/attachment", times: 1)
        end

        def test_upload_failure_rejects_subsequent_enqueues
          stub_request(:post, "#{API_URL}/attachment").to_return(status: 400)
          stub_status

          uploader = build_uploader
          assert uploader.enqueue(@ref, @data)
          uploader.force_flush(5.0)

          refute uploader.enqueue(@ref, @data), "after a failure, new jobs must be rejected"
          uploader.shutdown
        end

        def test_reports_error_status_on_failure
          stub_request(:post, "#{API_URL}/attachment").to_return(status: 400)
          stub_status

          uploader = build_uploader
          uploader.enqueue(@ref, @data)
          uploader.force_flush(5.0)
          uploader.shutdown

          assert_requested(:post, "#{API_URL}/attachment/status") do |req|
            body = JSON.parse(req.body)
            body["key"] == "test-key" && body.dig("status", "upload_status") == "error"
          end
        end

        def test_shutdown_is_idempotent
          stub_signed_url
          stub_upload
          stub_status

          uploader = build_uploader
          uploader.enqueue(@ref, @data)
          uploader.shutdown
          uploader.shutdown # must not raise or hang
          assert uploader.shutdown?
        end

        def test_enqueue_rejected_after_shutdown
          uploader = build_uploader
          uploader.shutdown
          refute uploader.enqueue(@ref, @data)
        end

        def test_resolves_org_id_via_login_when_not_provided
          stub_request(:post, "#{API_URL}/api/apikey/login")
            .to_return(status: 200, body: JSON.generate({"org_info" => [{"id" => "resolved-org"}]}))
          stub_signed_url
          stub_upload
          stub_status

          uploader = S3Uploader.new(api_key: "test-api-key", api_url: API_URL, initial_backoff: 0.01)
          uploader.enqueue(@ref, @data)
          uploader.force_flush(5.0)
          uploader.shutdown

          assert_requested(:post, "#{API_URL}/api/apikey/login")
          assert_requested(:post, "#{API_URL}/attachment") { |req| JSON.parse(req.body)["org_id"] == "resolved-org" }
        end

        def test_login_resolved_once_for_multiple_uploads
          stub_request(:post, "#{API_URL}/api/apikey/login")
            .to_return(status: 200, body: JSON.generate({"org_info" => [{"id" => "resolved-org"}]}))
          stub_signed_url
          stub_upload
          stub_status

          uploader = S3Uploader.new(api_key: "test-api-key", api_url: API_URL, initial_backoff: 0.01)
          3.times { uploader.enqueue(@ref, @data) }
          uploader.force_flush(5.0)
          uploader.shutdown

          assert_requested(:post, "#{API_URL}/api/apikey/login", times: 1)
        end

        def test_force_flush_times_out_when_not_drained
          # Signed URL request blocks long enough to exceed the flush timeout.
          stub_request(:post, "#{API_URL}/attachment").to_return do
            sleep 0.5
            {status: 200, body: JSON.generate({"signedUrl" => SIGNED_URL, "headers" => {}})}
          end
          stub_upload
          stub_status

          uploader = build_uploader
          uploader.enqueue(@ref, @data)
          refute uploader.force_flush(0.05), "force_flush should report timeout"
          uploader.shutdown
        end
      end
    end
  end
end
