# frozen_string_literal: true

require_relative "../patcher"
require_relative "instrumentation/messages"
require_relative "instrumentation/beta_messages"

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

      # Patcher for Anthropic beta messages API.
      # Instruments client.beta.messages.create and stream methods.
      #
      # @note Beta APIs are experimental and subject to change between SDK versions.
      #   Braintrust will make reasonable efforts to maintain compatibility, but
      #   breaking changes may require SDK updates.
      #
      # @see https://docs.anthropic.com/en/docs/build-with-claude/structured-outputs
      #   for structured outputs documentation
      class BetaMessagesPatcher < Braintrust::Contrib::Patcher
        # Version constraints for beta patcher.
        # Set MAXIMUM_VERSION when a breaking change is discovered to disable
        # beta instrumentation on incompatible versions until a fix is released.
        # Currently nil = rely on class existence check only.
        MAXIMUM_VERSION = nil

        class << self
          def applicable?
            return false unless defined?(::Anthropic::Client)
            return false unless defined?(::Anthropic::Resources::Beta::Messages)
            return false if MAXIMUM_VERSION && !version_compatible?
            true
          end

          def patched?(**options)
            target_class = get_singleton_class(options[:target]) || ::Anthropic::Resources::Beta::Messages
            Instrumentation::BetaMessages.applied?(target_class)
          end

          # Perform the actual patching.
          # @param options [Hash] Configuration options passed from integration
          # @option options [Object] :target Optional target instance to patch
          # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
          # @return [void]
          def perform_patch(**options)
            return unless applicable?

            Braintrust::Log.debug("Instrumenting Anthropic beta.messages API (experimental)")

            # MessageStream is shared with stable API - already patched by MessagesPatcher.
            # The BetaMessages instrumentation sets api_version: "beta" in context,
            # which MessageStream uses to include in metadata.
            patch_message_stream

            if options[:target]
              # Instance-level (for only this client instance)
              raise ArgumentError, "target must be a kind of ::Anthropic::Client" unless options[:target].is_a?(::Anthropic::Client)

              get_singleton_class(options[:target]).include(Instrumentation::BetaMessages)
            else
              # Class-level (for all client instances)
              ::Anthropic::Resources::Beta::Messages.include(Instrumentation::BetaMessages)
            end
          end

          private

          def version_compatible?
            return true unless MAXIMUM_VERSION

            spec = Gem.loaded_specs["anthropic"]
            return true unless spec

            spec.version <= Gem::Version.new(MAXIMUM_VERSION)
          end

          def get_singleton_class(client)
            client&.beta&.messages&.singleton_class
          rescue
            # Defensive: beta namespace may not exist or may have changed
            nil
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
