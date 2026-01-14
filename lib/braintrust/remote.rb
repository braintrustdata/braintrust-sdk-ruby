# frozen_string_literal: true

require_relative "remote/parameters"
require_relative "remote/prompt"
require_relative "remote/eval_case"
require_relative "remote/eval_hooks"
require_relative "remote/scorer_utils"
require_relative "remote/evaluator"
require_relative "remote/eval_runner"
require_relative "remote/sse"
require_relative "remote/data_resolver"
require_relative "remote/remote_scorer"
require_relative "remote/server_helpers"
require_relative "remote/request_context"
require_relative "remote/handlers"

module Braintrust
  # Remote evaluation module for defining evaluators that integrate with the Braintrust playground.
  #
  # This module provides PORO (Plain Old Ruby Object) classes for:
  # - Defining evaluators with a simple DSL
  # - Running evaluations with configurable parameters
  # - SSE serialization and streaming response bodies
  # - Server helpers for CORS, authentication, and data resolution
  # - Request handlers for /list and /eval endpoints
  #
  # All classes are dependency-free (no rack/rails required) and can be used
  # with any Ruby web framework.
  #
  # To use these evaluators with the Braintrust playground, you need to build a server
  # that exposes `/list` and `/eval` endpoints. See docs/REMOTE_EVALS.md for guidance.
  #
  # == Server Helper Classes
  #
  # - {ServerHelpers::CORS} - CORS headers and origin validation
  # - {ServerHelpers::Auth} - Token extraction from headers
  # - {DataResolver} - Resolve data specs into EvalCase arrays
  # - {RemoteScorer} - Invoke Braintrust functions as scorers
  # - {RequestContext} - Authentication context with State and API
  # - {Handlers} - Endpoint handlers for /list and /eval
  # - {SSE} - SSE serialization and streaming bodies
  #
  # @example Define an evaluator
  #   Braintrust::Remote.evaluator("My Evaluator") do
  #     task do |input, hooks|
  #       model = hooks.parameters[:model]
  #       # Call your AI service
  #       "result"
  #     end
  #
  #     scores [
  #       ->(input:, output:, expected:, **) { output == expected ? 1.0 : 0.0 }
  #     ]
  #
  #     parameters do
  #       string :model, default: "gpt-4o", description: "Model to use"
  #       number :temperature, default: 0.7, min: 0.0, max: 2.0
  #     end
  #   end
  #
  # @see Braintrust::Remote::Evaluator
  # @see Braintrust::Remote::EvalRunner
  # @see Braintrust::Remote::SSE
  #
  module Remote
    class << self
      # Global registry of evaluators
      def evaluators
        @evaluators ||= {}
      end

      # Register an evaluator
      def register_evaluator(evaluator)
        evaluators[evaluator.name] = evaluator
      end

      # Clear all registered evaluators (useful for testing)
      def clear_evaluators!
        @evaluators = {}
      end

      # Create a new evaluator using DSL
      # @param name [String] Name of the evaluator
      # @param options [Hash] Additional options (project_name, experiment_name, description)
      # @yield Block for defining the evaluator using DSL
      # @return [Evaluator] The created evaluator
      def evaluator(name, **options, &block)
        eval = Evaluator.new(name, **options, &block)
        register_evaluator(eval)
        eval
      end

      # Alias for evaluator
      def eval(name, **options, &block)
        evaluator(name, **options, &block)
      end
    end
  end
end

# Convenience method at top level
# @example
#   Braintrust.remote_eval("My Evaluator") do
#     task { |input| "result" }
#   end
module Braintrust
  class << self
    # Create a new remote evaluator using DSL
    # @param name [String] Name of the evaluator
    # @param options [Hash] Additional options
    # @yield Block for defining the evaluator
    # @return [Remote::Evaluator] The created evaluator
    def remote_eval(name, **options, &block)
      Remote.evaluator(name, **options, &block)
    end
  end
end
