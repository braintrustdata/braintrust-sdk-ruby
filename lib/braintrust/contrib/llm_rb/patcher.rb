# frozen_string_literal: true

require_relative "../patcher"
require_relative "instrumentation/context"

module Braintrust
  module Contrib
    module LlmRb
      # Patcher for llm.rb chat context.
      # Instruments LLM::Context#talk to trace chat completions.
      class ContextPatcher < Braintrust::Contrib::Patcher
        class << self
          def applicable?
            defined?(::LLM::Context)
          end

          def patched?(**options)
            target_class = options[:target]&.singleton_class || ::LLM::Context
            Instrumentation::Context.applied?(target_class)
          end

          # Perform the actual patching.
          # @param options [Hash] Configuration options
          # @option options [LLM::Context] :target Optional context instance to patch
          # @option options [OpenTelemetry::SDK::Trace::TracerProvider] :tracer_provider Optional
          # @return [void]
          def perform_patch(**options)
            return unless applicable?

            if options[:target]
              unless options[:target].is_a?(::LLM::Context)
                raise ArgumentError, "target must be a kind of ::LLM::Context"
              end

              options[:target].singleton_class.include(Instrumentation::Context)
            else
              ::LLM::Context.include(Instrumentation::Context)
            end
          end
        end
      end
    end
  end
end
