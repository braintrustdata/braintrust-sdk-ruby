module Test
  module Support
    module EvalHelper
      # Evaluator subclass that injects an explicit tracer_provider into every run,
      # preventing tests from registering proxy tracers on the global OTel provider.
      class TestEvaluator < Braintrust::Eval::Evaluator
        def initialize(tracer_provider:, **kwargs)
          super(**kwargs)
          @tracer_provider = tracer_provider
        end

        def run(cases, **opts)
          opts[:tracer_provider] ||= @tracer_provider
          super
        end
      end
    end
  end
end
