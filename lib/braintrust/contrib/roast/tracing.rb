# frozen_string_literal: true

module Braintrust
  module Contrib
    module Roast
      module Tracing
        INSTRUMENTATION_NAME = "braintrust.contrib.roast"

        def self.tracer_for(target)
          Braintrust::Contrib.tracer_for(target, name: INSTRUMENTATION_NAME)
        end
      end
    end
  end
end
