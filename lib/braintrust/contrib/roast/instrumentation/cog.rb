# frozen_string_literal: true

require_relative "../../support/otel"
require_relative "../tracing"

module Braintrust
  module Contrib
    module Roast
      module Instrumentation
        # Wrap the asynchronous work block rather than Cog#run! itself: run! only
        # schedules a task, while the cog executes later in a different fiber.
        module Cog
          class BarrierProxy
            def initialize(barrier, &around_task)
              @barrier = barrier
              @around_task = around_task
            end

            def async(**options, &task)
              @barrier.async(**options) do |async_task|
                @around_task.call(async_task, task)
              end
            end
          end

          def run!(barrier, config, input_context, executor_scope_value, executor_scope_index)
            parent_context = roast_parent_context
            return super unless tracing_enabled? && parent_context

            tracer = Braintrust::Contrib::Roast::Tracing.tracer_for(self)
            proxy = BarrierProxy.new(barrier) do |async_task, task|
              ::OpenTelemetry::Context.with_current(parent_context) do
                span_name = "roast.cog.#{name}"
                tracer.in_span(span_name) do |span|
                  # Braintrust uses span_attributes for type/name; Roast details go in metadata.
                  Support::OTel.set_json_attr(span, "braintrust.span_attributes", {type: "task", name: span_name})
                  Braintrust::Contrib::Context.set!(self, roast_span_context: ::OpenTelemetry::Context.current)
                  task.call(async_task)
                rescue => e
                  span.record_exception(e)
                  span.status = ::OpenTelemetry::Trace::Status.error(e.message)
                  raise
                ensure
                  record_outcome(span)
                end
              end
            end
            super(proxy, config, input_context, executor_scope_value, executor_scope_index)
          end

          private

          def roast_parent_context
            path = ::Roast::TaskContext.path
            path.reverse_each do |element|
              context = Braintrust::Contrib.context_for(element.cog)&.[](:roast_span_context)
              return context if context
            end
            path.reverse_each do |element|
              context = Braintrust::Contrib.context_for(element.execution_manager&.workflow_context)&.[](:roast_span_context)
              return context if context
            end
            nil
          end

          def tracing_enabled?
            context = Braintrust::Contrib.context_for(self)
            class_context = Braintrust::Contrib.context_for(self.class)
            context&.[](:enabled) != false && class_context&.[](:enabled) != false
          end

          def record_outcome(span)
            outcome = if failed?
              "failed"
            elsif skipped?
              "skipped"
            else
              "completed"
            end
            Support::OTel.set_json_attr(span, "braintrust.metadata", {
              "cog_type" => type,
              "cog_name" => name.to_s,
              "outcome" => outcome
            })

            output_value = output.response if output&.respond_to?(:response)
            Support::OTel.set_json_attr(span, "braintrust.output_json", output_value) if output_value.is_a?(String)
            span.status = ::OpenTelemetry::Trace::Status.error("Cog failed") if failed?
          end
        end
      end
    end
  end
end
