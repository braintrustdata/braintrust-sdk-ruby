# frozen_string_literal: true

require_relative "../../support/otel"
require_relative "../tracing"

module Braintrust
  module Contrib
    module Roast
      module Instrumentation
        # from_file enters a new Async fiber, so carry its caller's OTel context
        # through the params object that is handed to the workflow.
        module WorkflowClass
          def from_file(workflow_path, params)
            previous_parent = Braintrust::Contrib.context_for(params)&.[](:roast_parent_context)
            Braintrust::Contrib::Context.set!(params, roast_parent_context: ::OpenTelemetry::Context.current)
            super
          ensure
            Braintrust::Contrib::Context.set!(params, roast_parent_context: previous_parent)
          end
        end

        module Workflow
          def start!
            context = Braintrust::Contrib.context_for(self)
            class_context = Braintrust::Contrib.context_for(self.class)
            return super if context&.[](:enabled) == false || class_context&.[](:enabled) == false

            tracer = Braintrust::Contrib::Roast::Tracing.tracer_for(self)
            workflow_context = @workflow_context
            workflow_path = @workflow_path
            params = workflow_context.params
            parent_context = Braintrust::Contrib.context_for(params)&.[](:roast_parent_context)
            trace_workflow = proc do
              tracer.in_span("roast.workflow") do |span|
                Support::OTel.set_json_attr(span, "braintrust.span_attributes", {type: "task", name: "roast.workflow"})
                Support::OTel.set_json_attr(span, "braintrust.metadata", {"contrib.roast.workflow.name" => File.basename(workflow_path.to_s)})
                input = {targets: params.targets, args: params.args, kwargs: params.kwargs}.reject { |_, value| value.nil? || value.empty? }
                Support::OTel.set_json_attr(span, "braintrust.input_json", input) unless input.empty?
                Braintrust::Contrib::Context.set!(workflow_context, roast_span_context: ::OpenTelemetry::Context.current)
                super()
              end
            end
            parent_context ? ::OpenTelemetry::Context.with_current(parent_context, &trace_workflow) : trace_workflow.call
          end
        end
      end
    end
  end
end
