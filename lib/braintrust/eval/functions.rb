# frozen_string_literal: true

require_relative "../functions"

module Braintrust
  module Eval
    # @deprecated Use {Braintrust::Functions} instead.
    module Functions
      class << self
        # @deprecated Use {Braintrust::Functions.task} instead.
        def task(**kwargs)
          Log.warn_once(:eval_functions_task, "Braintrust::Eval::Functions.task is deprecated: use Braintrust::Functions.task instead.")
          Braintrust::Functions.task(**kwargs)
        end

        # @deprecated Use {Braintrust::Functions.scorer} instead.
        def scorer(**kwargs)
          Log.warn_once(:eval_functions_scorer, "Braintrust::Eval::Functions.scorer is deprecated: use Braintrust::Functions.scorer instead.")
          Braintrust::Functions.scorer(**kwargs)
        end
      end
    end
  end
end
