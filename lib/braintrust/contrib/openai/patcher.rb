# frozen_string_literal: true

require_relative "../patcher"
require_relative "instrumentation/chat"
require_relative "instrumentation/responses"
require_relative "instrumentation/moderations"

module Braintrust
  module Contrib
    module OpenAI
      # Patcher for OpenAI integration - implements class-level patching.
      # All new OpenAI::Client instances created after patch! will be automatically instrumented.
      class ChatPatcher < Braintrust::Contrib::Patcher
        class << self
          def applicable?
            defined?(::OpenAI::Client)
          end

          def patched?(**options)
            # Use the target's singleton class if provided, otherwise check the base class.
            target_class = get_singleton_class(options[:target]) || ::OpenAI::Resources::Chat::Completions

            Instrumentation::Chat::Completions.applied?(target_class)
          end

          # Perform the actual patching.
          # @param options [Hash] Configuration options passed from integration
          # @option options [Object] :target Optional target instance to patch
          # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
          # @return [void]
          def perform_patch(**options)
            return unless applicable?

            # Stream classes are shared across all clients, patch at class level.
            # The instrumentation short-circuits when no context is present,
            # so uninstrumented clients' streams pass through unaffected.
            patch_stream_classes

            if options[:target]
              # Instance-level (for only this client)
              raise ArgumentError, "target must be a kind of ::OpenAI::Client" unless options[:target].is_a?(::OpenAI::Client)

              get_singleton_class(options[:target]).include(Instrumentation::Chat::Completions)
            else
              # Class-level (for all clients)
              ::OpenAI::Resources::Chat::Completions.include(Instrumentation::Chat::Completions)
            end
          end

          def patch_stream_classes
            # Patch ChatCompletionStream for stream() method
            if defined?(::OpenAI::Helpers::Streaming::ChatCompletionStream)
              unless Instrumentation::Chat::ChatCompletionStream.applied?(::OpenAI::Helpers::Streaming::ChatCompletionStream)
                ::OpenAI::Helpers::Streaming::ChatCompletionStream.include(Instrumentation::Chat::ChatCompletionStream)
              end
            end

            # Patch Internal::Stream for stream_raw() method
            if defined?(::OpenAI::Internal::Stream)
              unless Instrumentation::Chat::InternalStream.applied?(::OpenAI::Internal::Stream)
                ::OpenAI::Internal::Stream.include(Instrumentation::Chat::InternalStream)
              end
            end
          end

          private

          def get_singleton_class(client)
            client&.chat&.completions&.singleton_class
          end
        end
      end

      # Patcher for OpenAI integration - implements class-level patching.
      # All new OpenAI::Client instances created after patch! will be automatically instrumented.
      class ResponsesPatcher < Braintrust::Contrib::Patcher
        class << self
          def applicable?
            defined?(::OpenAI::Client) && ::OpenAI::Client.instance_methods.include?(:responses)
          end

          def patched?(**options)
            # Use the target's singleton class if provided, otherwise check the base class.
            target_class = get_singleton_class(options[:target]) || ::OpenAI::Resources::Responses

            Instrumentation::Responses.applied?(target_class)
          end

          # Perform the actual patching.
          # @param options [Hash] Configuration options passed from integration
          # @option options [Object] :target Optional target instance to patch
          # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
          # @return [void]
          def perform_patch(**options)
            return unless applicable?

            # Stream class is shared across all clients, patch at class level.
            # The instrumentation short-circuits when no context is present,
            # so uninstrumented clients' streams pass through unaffected.
            patch_response_stream

            if options[:target]
              # Instance-level (for only this client)
              raise ArgumentError, "target must be a kind of ::OpenAI::Client" unless options[:target].is_a?(::OpenAI::Client)

              get_singleton_class(options[:target]).include(Instrumentation::Responses)
            else
              # Class-level (for all clients)
              ::OpenAI::Resources::Responses.include(Instrumentation::Responses)
            end
          end

          def patch_response_stream
            # Patch ResponseStream for stream() method
            if defined?(::OpenAI::Helpers::Streaming::ResponseStream)
              unless Instrumentation::ResponseStream.applied?(::OpenAI::Helpers::Streaming::ResponseStream)
                ::OpenAI::Helpers::Streaming::ResponseStream.include(Instrumentation::ResponseStream)
              end
            end
          end

          private

          def get_singleton_class(client)
            client&.responses&.singleton_class
          end
        end
      end

      # Patcher for OpenAI Moderations API - implements class-level patching.
      # All new OpenAI::Client instances created after patch! will be automatically instrumented.
      class ModerationsPatcher < Braintrust::Contrib::Patcher
        class << self
          def applicable?
            defined?(::OpenAI::Client) && ::OpenAI::Client.instance_methods.include?(:moderations)
          end

          def patched?(**options)
            # Use the target's singleton class if provided, otherwise check the base class.
            target_class = get_singleton_class(options[:target]) || ::OpenAI::Resources::Moderations

            Instrumentation::Moderations.applied?(target_class)
          end

          # Perform the actual patching.
          # @param options [Hash] Configuration options passed from integration
          # @option options [Object] :target Optional target instance to patch
          # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional tracer provider
          # @return [void]
          def perform_patch(**options)
            return unless applicable?

            if options[:target]
              # Instance-level (for only this client)
              raise ArgumentError, "target must be a kind of ::OpenAI::Client" unless options[:target].is_a?(::OpenAI::Client)

              get_singleton_class(options[:target]).include(Instrumentation::Moderations)
            else
              # Class-level (for all clients)
              ::OpenAI::Resources::Moderations.include(Instrumentation::Moderations)
            end
          end

          private

          def get_singleton_class(client)
            client&.moderations&.singleton_class
          end
        end
      end
    end
  end
end
