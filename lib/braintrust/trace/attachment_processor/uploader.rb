# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "../../internal/http"
require_relative "../../logger"

module Braintrust
  module Trace
    module AttachmentProcessor
      # Uploader that accepts all jobs but does nothing. Useful for testing the
      # processor in isolation and for btx replay mode (where no real upload is
      # performed but the reference rewriting still happens).
      class NoopUploader
        def initialize
          @shutdown = false
          @mutex = Mutex.new
        end

        # @return [Boolean] true unless shut down
        def enqueue(_ref, _data)
          @mutex.synchronize { !@shutdown }
        end

        # @return [Boolean] always true
        def force_flush(_timeout = nil)
          true
        end

        def shutdown
          @mutex.synchronize { @shutdown = true }
        end

        # @return [Boolean]
        def shutdown?
          @mutex.synchronize { @shutdown }
        end
      end

      # Background uploader that pushes attachment data to Braintrust object
      # storage via signed URLs.
      #
      # A single daemon thread pulls jobs from a bounded queue and runs the
      # three-step upload flow (request signed URL, PUT data, report status).
      # The actual uploads never block the app thread.
      #
      # On any upload-pipeline failure the uploader shuts itself down so that
      # subsequent spans skip attachment processing entirely (and are exported
      # with inline base64) rather than producing references whose data never
      # lands in storage.
      class S3Uploader
        DEFAULT_MAX_RETRIES = 8
        DEFAULT_INITIAL_BACKOFF = 0.5
        DEFAULT_QUEUE_SIZE = 1024
        DEFAULT_SHUTDOWN_TIMEOUT = 120.0

        # @param api_key [String]
        # @param api_url [String] base URL for the Braintrust API (e.g. https://api.braintrust.dev)
        # @param login_url [String, nil] app URL for the login endpoint (defaults to api_url)
        # @param org_id [String, nil] pre-resolved org id; resolved via login when omitted
        # @param logger [#warn, #debug, nil]
        # @param max_retries [Integer]
        # @param initial_backoff [Float] seconds
        # @param queue_size [Integer]
        # @param shutdown_timeout [Float] seconds
        def initialize(api_key:, api_url:, login_url: nil, org_id: nil, logger: nil,
          max_retries: DEFAULT_MAX_RETRIES, initial_backoff: DEFAULT_INITIAL_BACKOFF,
          queue_size: DEFAULT_QUEUE_SIZE, shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT)
          @api_key = api_key
          @api_url = api_url.to_s.sub(%r{/+\z}, "")
          @login_url = (login_url || api_url).to_s.sub(%r{/+\z}, "")
          @org_id = org_id
          @logger = logger || Braintrust::Log
          @max_retries = max_retries
          @initial_backoff = initial_backoff
          @shutdown_timeout = shutdown_timeout

          @queue = SizedQueue.new(queue_size)
          @mutex = Mutex.new
          @reject_new_jobs = false
          @worker_started = false
          @worker = nil
          @shutdown_done = false

          # Tracks in-flight jobs (queued but not yet completed) so force_flush
          # can wait for quiescence.
          @inflight_mutex = Mutex.new
          @inflight_cond = ConditionVariable.new
          @inflight = 0

          # Signals the worker to stop and cancels any retry backoff sleep.
          @stop_mutex = Mutex.new
          @stop_cond = ConditionVariable.new
          @stopping = false

          # Single-flight org-id resolution.
          @org_mutex = Mutex.new
          @org_resolved = false
          @org_error = nil
        end

        # Enqueue an attachment for background upload.
        #
        # @return [Boolean] false if shut down or the queue is full
        def enqueue(ref, data)
          @mutex.synchronize do
            return false if @reject_new_jobs

            ensure_worker_started

            # Bump in-flight before pushing so force_flush can't observe an
            # idle state between push and the worker picking it up.
            @inflight_mutex.synchronize { @inflight += 1 }

            begin
              @queue.push({ref: ref, data: data}, true) # non-blocking
              true
            rescue ThreadError
              # Queue full.
              @inflight_mutex.synchronize do
                @inflight -= 1
                @inflight_cond.broadcast
              end
              false
            end
          end
        end

        # Block until all currently-enqueued uploads complete or +timeout+
        # seconds elapse.
        #
        # @param timeout [Float, nil]
        # @return [Boolean] true if drained, false on timeout
        def force_flush(timeout = nil)
          deadline = timeout ? monotonic_now + timeout : nil
          @inflight_mutex.synchronize do
            while @inflight > 0
              if deadline
                remaining = deadline - monotonic_now
                return false if remaining <= 0

                @inflight_cond.wait(@inflight_mutex, remaining)
              else
                @inflight_cond.wait(@inflight_mutex)
              end
            end
          end
          true
        end

        # Stop the uploader, draining remaining jobs. Idempotent.
        def shutdown
          worker = nil
          @mutex.synchronize do
            return if @shutdown_done

            @shutdown_done = true
            @reject_new_jobs = true
            worker = @worker
          end

          # Cancel any in-progress retry backoff and tell the worker to drain.
          @stop_mutex.synchronize do
            @stopping = true
            @stop_cond.broadcast
          end

          if worker
            unless worker.join(@shutdown_timeout)
              @logger.warn("Braintrust: attachment uploader shutdown timed out")
            end
          end
        end

        # @return [Boolean]
        def shutdown?
          @mutex.synchronize { @reject_new_jobs }
        end

        private

        # Must be called with @mutex held.
        def ensure_worker_started
          return if @worker_started

          @worker_started = true
          @worker = Thread.new { worker_loop }
          @worker.name = "braintrust-attachment-uploader"
        end

        def worker_loop
          @logger.debug("Braintrust: attachment uploader worker started")
          loop do
            job = next_job
            break if job.nil?

            process_job(job)
          end
          @logger.debug("Braintrust: attachment uploader worker stopped")
        end

        # Returns the next job, or nil when the uploader is stopping and the
        # queue is drained.
        def next_job
          loop do
            begin
              return @queue.pop(true) # non-blocking
            rescue ThreadError
              # Queue empty.
            end

            return nil if stopping?

            # Wait briefly for either a new job or a stop signal.
            @stop_mutex.synchronize do
              @stop_cond.wait(@stop_mutex, 0.05) unless @stopping
            end
          end
        end

        # Run a single upload with rescue so an unexpected exception does not
        # kill the worker permanently. Treat any crash as an upload failure.
        def process_job(job)
          upload(job)
        rescue => e
          @logger.error("Braintrust: attachment upload crashed: #{e.class}: #{e.message}")
          fail_and_reject
        ensure
          @inflight_mutex.synchronize do
            @inflight -= 1
            @inflight_cond.broadcast
          end
        end

        def upload(job)
          ref = job[:ref]
          data = job[:data]

          org_id = resolve_org_id
          unless org_id
            report_status(ref.key, "error", @org_error.to_s)
            fail_and_reject
            return
          end

          signed_url, headers = request_upload_url(org_id, ref)
          unless signed_url
            report_status(ref.key, "error", "failed to request upload URL")
            fail_and_reject
            return
          end

          if upload_to_signed_url(signed_url, headers, ref.content_type, data)
            report_status(ref.key, "done")
          else
            report_status(ref.key, "error", "failed to upload to signed URL")
            fail_and_reject
          end
        end

        def fail_and_reject
          already = false
          @mutex.synchronize do
            already = @reject_new_jobs
            @reject_new_jobs = true
          end
          unless already
            @logger.warn("Braintrust: attachment uploader shutting down due to upload failure; " \
              "subsequent spans will be exported with inline base64")
          end
        end

        # ── org id resolution (single-flight) ────────────────────────────

        def resolve_org_id
          @org_mutex.synchronize do
            return @org_id if @org_resolved || @org_id

            begin
              @org_id = fetch_org_id
            rescue => e
              @org_error = e
              @logger.warn("Braintrust: failed to resolve org id for attachment upload: #{e.message}")
            ensure
              @org_resolved = true
            end
            @org_id
          end
        end

        def fetch_org_id
          uri = URI("#{@login_url}/api/apikey/login")
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{@api_key}"
          request["Content-Type"] = "application/json"

          response = Braintrust::Internal::Http.with_redirects(uri, request)
          unless response.is_a?(Net::HTTPSuccess)
            raise Error, "login returned status #{response.code}"
          end

          body = JSON.parse(response.body)
          org_info = body["org_info"]
          raise Error, "no org info returned from login" unless org_info.is_a?(Array) && !org_info.empty?

          org_info.first["id"]
        end

        # ── three-step upload flow ───────────────────────────────────────

        def request_upload_url(org_id, ref)
          uri = URI("#{@api_url}/attachment")
          payload = {
            key: ref.key,
            filename: ref.filename,
            content_type: ref.content_type,
            org_id: org_id
          }
          body = do_with_retry(:post, uri, JSON.generate(payload), content_type: "application/json", auth: true)
          return [nil, nil] unless body

          parsed = JSON.parse(body)
          signed_url = parsed["signedUrl"]
          return [nil, nil] if signed_url.nil? || signed_url.empty?

          headers = parsed["headers"]
          headers = {} unless headers.is_a?(Hash)
          [signed_url, headers]
        rescue JSON::ParserError
          [nil, nil]
        end

        def upload_to_signed_url(signed_url, headers, content_type, data)
          uri = URI(signed_url)
          request = Net::HTTP::Put.new(uri)
          request.body = data
          request["Content-Type"] = content_type
          headers.each { |k, v| request[k] = v }
          add_provider_specific_headers(uri, request)

          response = do_request_with_retry(uri, request)
          response&.is_a?(Net::HTTPSuccess) || false
        end

        def report_status(key, status, error_message = nil)
          org_id = resolve_org_id
          return unless org_id

          status_map = {upload_status: status}
          status_map[:error_message] = error_message if error_message && !error_message.empty?

          payload = {key: key, org_id: org_id, status: status_map}
          uri = URI("#{@api_url}/attachment/status")
          do_with_retry(:post, uri, JSON.generate(payload), content_type: "application/json", auth: true)
        rescue => e
          @logger.warn("Braintrust: failed to report attachment status (#{status}): #{e.message}")
        end

        # ── HTTP helpers ─────────────────────────────────────────────────

        # @return [String, nil] response body on success, nil on failure
        def do_with_retry(method, uri, body, content_type:, auth:)
          klass = (method == :post) ? Net::HTTP::Post : Net::HTTP::Get
          request = klass.new(uri)
          request.body = body if body
          request["Content-Type"] = content_type
          request["Authorization"] = "Bearer #{@api_key}" if auth

          response = do_request_with_retry(uri, request)
          return nil unless response&.is_a?(Net::HTTPSuccess)

          response.body
        end

        # Execute a request with exponential backoff. Retries on 5xx and network
        # errors; never retries 4xx. The backoff sleep is cancellable by
        # shutdown. Returns the final response, or nil if all attempts failed.
        def do_request_with_retry(uri, request)
          backoff = @initial_backoff
          last_response = nil

          (0..@max_retries).each do |attempt|
            if attempt > 0
              return nil if sleep_or_cancel(backoff)

              backoff *= 2
            end

            begin
              response = Braintrust::Internal::Http.with_redirects(uri, request)
            rescue => e
              @logger.debug("Braintrust: attachment request error (attempt #{attempt}): #{e.message}")
              next
            end

            return response if response.code.to_i < 500

            last_response = response
          end

          last_response
        end

        # Sleep up to +seconds+, returning true early if shutdown was requested.
        def sleep_or_cancel(seconds)
          @stop_mutex.synchronize do
            return true if @stopping

            @stop_cond.wait(@stop_mutex, seconds)
            @stopping
          end
        end

        def add_provider_specific_headers(uri, request)
          # Azure Blob Storage requires this header on PUT uploads.
          if uri.host&.end_with?(".blob.core.windows.net")
            request["x-ms-blob-type"] = "BlockBlob"
          end
        end

        def stopping?
          @stop_mutex.synchronize { @stopping }
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
