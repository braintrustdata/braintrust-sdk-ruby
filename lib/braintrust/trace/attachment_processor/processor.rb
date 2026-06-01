# frozen_string_literal: true

require "json"
require_relative "formats"
require_relative "uploader"

module Braintrust
  module Trace
    module AttachmentProcessor
      # Scans JSON strings for base64 attachments across multiple LLM provider
      # formats, uploads them, and returns modified JSON with attachment
      # references in place of the inline base64 data.
      class Processor
        # Maximum JSON nesting depth to recurse into. Pathological deeply-nested
        # input returns unchanged once this cap is hit, rather than exhausting
        # the stack.
        MAX_WALK_DEPTH = 128

        # @return [#enqueue, #shutdown?, #force_flush] the background uploader
        attr_reader :uploader

        # @param uploader [#enqueue, #shutdown?] background attachment uploader
        # @param logger [#warn, #debug, nil] optional logger
        # @param formats [Array<Formats::Format>] vendor formats to apply
        # @param json_max_nesting [Integer, false] nesting limit passed to
        #   JSON.parse/JSON.generate. Defaults to MAX_WALK_DEPTH so the parser
        #   and the walker agree on the depth cap.
        def initialize(uploader:, logger: nil, formats: Formats.all, json_max_nesting: MAX_WALK_DEPTH)
          @uploader = uploader
          @logger = logger
          @formats = formats
          @heuristic = Formats.build_heuristic(formats)
          @json_max_nesting = json_max_nesting
        end

        # Scan +json_str+ for base64 attachments, upload them, and return the
        # modified JSON.
        #
        # Returns the original string unchanged when:
        # - it is nil/empty, or the uploader has shut down,
        # - the fast-path heuristic finds nothing,
        # - the JSON cannot be parsed (per-span error; does not shut anything down),
        # - no attachment was found, or
        # - any enqueue failed mid-walk (partial-replacement safety).
        #
        # @param json_str [String, nil]
        # @return [String, nil]
        def process_and_upload(json_str)
          return json_str if json_str.nil? || json_str.empty?
          return json_str if @uploader.shutdown?
          return json_str unless @heuristic.match?(json_str)

          process_json(json_str)
        rescue JSON::ParserError => e
          # Per-span error: skip this span, do not poison the processor for
          # other spans. The heuristic can match on non-LLM spans whose
          # attributes merely look like base64.
          @logger&.debug("attachment processing skipped for span: #{e.message}")
          json_str
        end

        private

        def process_json(json_str)
          root = JSON.parse(json_str, max_nesting: @json_max_nesting)

          state = WalkState.new
          result = walk_and_replace(root, "", state, 0)

          return json_str if state.failed || !state.modified

          JSON.generate(result, max_nesting: @json_max_nesting)
        end

        # Mutable accumulator threaded through the walk.
        class WalkState
          attr_accessor :modified, :failed

          def initialize
            @modified = false
            @failed = false
          end
        end

        # Traverse the JSON tree. For each node, check all formats in order; the
        # first whose matcher returns true handles the replacement and recursion
        # stops for that subtree. Otherwise recurse into children.
        #
        # If an enqueue fails, +state.failed+ is set and the partially-rewritten
        # tree is discarded by the caller.
        def walk_and_replace(node, parent_key, state, depth)
          return node if depth >= MAX_WALK_DEPTH || state.failed

          upload_fn = ->(ref, data) {
            ok = @uploader.enqueue(ref, data)
            state.failed = true unless ok
            ok
          }

          @formats.each do |fmt|
            next unless fmt.match.call(parent_key, node)

            replacement, ok = fmt.replace.call(node, upload_fn)
            if ok
              state.modified = true
              return replacement
            end
            # Replace returned false (e.g. decode failure / rejected upload).
            # state.failed is set by upload_fn when the rejection came from the
            # uploader; otherwise treat as a skip and fall through to recursion.
            return node if state.failed
          end

          case node
          when Hash
            result = nil
            node.each do |k, child|
              new_child = walk_and_replace(child, k, state, depth + 1)
              return node if state.failed

              if !new_child.equal?(child)
                result ||= node.dup
                result[k] = new_child
              end
            end
            result || node
          when Array
            result = nil
            node.each_with_index do |child, i|
              new_child = walk_and_replace(child, "", state, depth + 1)
              return node if state.failed

              if !new_child.equal?(child)
                result ||= node.dup
                result[i] = new_child
              end
            end
            result || node
          else
            node
          end
        end
      end
    end
  end
end
