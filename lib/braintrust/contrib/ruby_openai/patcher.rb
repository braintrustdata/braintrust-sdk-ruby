# frozen_string_literal: true

require_relative "../patcher"
require_relative "instrumentation/chat"
require_relative "instrumentation/responses"
require_relative "instrumentation/moderations"

module Braintrust
  module Contrib
    module RubyOpenAI
      # Patcher for ruby-openai chat completions.
      # Instruments OpenAI::Client#chat method.
      class ChatPatcher < Braintrust::Contrib::Patcher
        class << self
          def applicable?
            defined?(::OpenAI::Client)
          end

          def patched?(**options)
            target_class = options[:target]&.singleton_class || ::OpenAI::Client
            Instrumentation::Chat.applied?(target_class)
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

              options[:target].singleton_class.include(Instrumentation::Chat)
            else
              # Class-level (for all clients)
              ::OpenAI::Client.include(Instrumentation::Chat)
            end
          end
        end
      end

      # Patcher for ruby-openai responses API.
      # Instruments OpenAI::Responses#create method.
      class ResponsesPatcher < Braintrust::Contrib::Patcher
        class << self
          def applicable?
            defined?(::OpenAI::Client) && ::OpenAI::Client.method_defined?(:responses)
          end

          def patched?(**options)
            if options[:target]
              responses_obj = options[:target].responses
              Instrumentation::Responses.applied?(responses_obj.singleton_class)
            else
              # For class-level, check if the responses class is patched
              defined?(::OpenAI::Responses) && Instrumentation::Responses.applied?(::OpenAI::Responses)
            end
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

              responses_obj = options[:target].responses
              responses_obj.singleton_class.include(Instrumentation::Responses)
            else
              # Class-level (for all clients)
              ::OpenAI::Responses.include(Instrumentation::Responses)
            end
          end
        end
      end

      # Patcher for ruby-openai moderations API.
      # Instruments OpenAI::Client#moderations method.
      class ModerationsPatcher < Braintrust::Contrib::Patcher
        class << self
          def applicable?
            defined?(::OpenAI::Client) && ::OpenAI::Client.method_defined?(:moderations)
          end

          def patched?(**options)
            target_class = options[:target]&.singleton_class || ::OpenAI::Client
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

              options[:target].singleton_class.include(Instrumentation::Moderations)
            else
              # Class-level (for all clients)
              ::OpenAI::Client.include(Instrumentation::Moderations)
            end
          end
        end
      end
    end
  end
end
