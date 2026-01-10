# frozen_string_literal: true

require_relative "../patcher"
require_relative "instrumentation/chat"

module Braintrust
  module Contrib
    module RubyLLM
      # Patcher for RubyLLM chat completions.
      # Instruments RubyLLM::Chat#complete and #execute_tool methods.
      class ChatPatcher < Braintrust::Contrib::Patcher
        class << self
          def applicable?
            defined?(::RubyLLM::Chat)
          end

          def patched?(**options)
            target_class = options[:target]&.singleton_class || ::RubyLLM::Chat
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
              # Instance-level (for only this chat instance)
              raise ArgumentError, "target must be a kind of ::RubyLLM::Chat" unless options[:target].is_a?(::RubyLLM::Chat)

              options[:target].singleton_class.include(Instrumentation::Chat)
            else
              # Class-level (for all chat instances)
              ::RubyLLM::Chat.include(Instrumentation::Chat)
            end
          end
        end
      end
    end
  end
end
