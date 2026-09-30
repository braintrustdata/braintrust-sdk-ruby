# frozen_string_literal: true

require_relative "../patcher"
require_relative "instrumentation/workflow"
require_relative "instrumentation/cog"

module Braintrust
  module Contrib
    module Roast
      class WorkflowPatcher < Braintrust::Contrib::Patcher
        def self.applicable? = defined?(::Roast::Workflow)

        def self.patched?(**options)
          klass = options[:target]&.singleton_class || ::Roast::Workflow
          klass.ancestors.include?(Instrumentation::Workflow) &&
            (options[:target] || ::Roast::Workflow.singleton_class.ancestors.include?(Instrumentation::WorkflowClass))
        end

        def self.perform_patch(**options)
          target = options[:target]
          raise ArgumentError, "target must be a Roast::Workflow" if target && !target.is_a?(::Roast::Workflow)

          (target&.singleton_class || ::Roast::Workflow).prepend(Instrumentation::Workflow)
          ::Roast::Workflow.singleton_class.prepend(Instrumentation::WorkflowClass) unless target
        end
      end

      class CogPatcher < Braintrust::Contrib::Patcher
        def self.applicable? = defined?(::Roast::Cog)

        def self.patched?(**)
          ::Roast::Cog.ancestors.include?(Instrumentation::Cog)
        end

        def self.perform_patch(**)
          ::Roast::Cog.prepend(Instrumentation::Cog)
        end
      end
    end
  end
end
