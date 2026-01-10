# frozen_string_literal: true

require_relative "../patcher"
require_relative "instrumentation/messages"

module Braintrust
  module Contrib
    module Anthropic
      # Patcher for Anthropic messages.
      # Instruments Anthropic::Messages#create and #stream methods.
      class MessagesPatcher < Braintrust::Contrib::Patcher
        class << self
          def applicable?
            defined?(::Anthropic::Client)
          end

          def patched?(**options)
            target_class = get_singleton_class(options[:target]) || ::Anthropic::Resources::Messages
            Instrumentation::Messages.applied?(target_class)
          end

          # Perform the actual patching.
          # @param options [Hash] Configuration options passed from integration
          # @option options [Object] :target Optional target instance to patch
          # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
          # @return [void]
          def perform_patch(**options)
            return unless applicable?

            # MessageStream is shared across all clients, so patch at class level.
            # The instrumentation short-circuits when no context is present,
            # so uninstrumented clients' streams pass through unaffected.
            patch_message_stream

            if options[:target]
              # Instance-level (for only this client instance)
              raise ArgumentError, "target must be a kind of ::Anthropic::Client" unless options[:target].is_a?(::Anthropic::Client)

              get_singleton_class(options[:target]).include(Instrumentation::Messages)
            else
              # Class-level (for all client instances)
              ::Anthropic::Resources::Messages.include(Instrumentation::Messages)
            end
          end

          private

          def get_singleton_class(client)
            client&.messages&.singleton_class
          end

          def patch_message_stream
            return unless defined?(::Anthropic::Helpers::Streaming::MessageStream)
            return if Instrumentation::MessageStream.applied?(::Anthropic::Helpers::Streaming::MessageStream)

            ::Anthropic::Helpers::Streaming::MessageStream.include(Instrumentation::MessageStream)
          end
        end
      end
    end
  end
end
