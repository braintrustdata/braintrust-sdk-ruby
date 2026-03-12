# frozen_string_literal: true

require_relative "../scorer"

module Braintrust
  module Eval
    # @deprecated Use {Braintrust::Scorer} instead.
    module Scorer
      # @deprecated Use {Braintrust::Scorer.new} instead.
      def self.new(name_or_callable = nil, callable = nil, &block)
        Log.warn_once(:eval_scorer_class, "Braintrust::Eval::Scorer is deprecated: use Braintrust::Scorer.new instead.")

        if name_or_callable.is_a?(String) || name_or_callable.is_a?(Symbol)
          name = name_or_callable.to_s
          block = callable.method(:call) if callable && !block
        else
          resolved = name_or_callable || callable
          block = resolved.method(:call) if resolved && !block
          name = nil
        end

        scorer = Braintrust::Scorer.new(name, &block)
        scorer.singleton_class.prepend(PositionalArgsRemapping)
        scorer
      end

      # @deprecated Maps positional #call(input, expected, output, metadata) to keyword args.
      # Will be removed when the legacy Eval::Scorer API is removed.
      module PositionalArgsRemapping
        def call(*args, **kwargs)
          if args.any?
            Log.warn_once(:scorer_positional_call, "Calling a Scorer with positional args is deprecated: use keyword args (input:, expected:, output:, metadata:) instead.")
            kwargs = {input: args[0], expected: args[1], output: args[2], metadata: args[3]}
          end
          super(**kwargs)
        end
      end
    end
  end
end
