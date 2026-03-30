#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using parameters to configure evaluation behavior
#
# This example demonstrates how to:
# 1. Define a task that accepts `parameters:` for runtime configuration
# 2. Run Eval.run with `parameters:` to control task behavior
# 3. Use parameters in scorers for configurable scoring thresholds
#
# Parameters are passed as keyword arguments. Tasks and scorers that declare
# `parameters:` in their signature receive them automatically. Those that
# don't declare `parameters:` are unaffected — the SDK's KeywordFilter
# strips unknown kwargs before calling.
#
# This is especially useful for remote evals run from the Braintrust Playground,
# where the UI sends parameter values (e.g. model name, temperature) in the
# request body.
#
# Usage:
#   ruby examples/eval/parameters.rb

require "bundler/setup"
require "braintrust"
require "braintrust/eval"

Braintrust.init
at_exit { OpenTelemetry.tracer_provider.shutdown }

project_name = "ruby-sdk-examples"

# --- Task with parameters ---
#
# The task receives `parameters:` as a keyword argument.
# Here we use a "suffix" parameter to append to the output.
task = ->(input:, parameters:) {
  suffix = parameters["suffix"] || ""
  input.upcase + suffix
}

# --- Scorer with parameters ---
#
# Scorers can also access parameters. Here we use a configurable
# tolerance threshold for fuzzy matching.
scorer = Braintrust::Scorer.new("exact_with_params") do |expected:, output:, parameters:|
  threshold = parameters["threshold"] || 1.0
  (output == expected) ? 1.0 : (1.0 - threshold)
end

# --- Run evaluation ---
#
# Pass `parameters:` to Eval.run. Both the task and scorer receive them.
puts "Running evaluation with parameters: suffix='!', threshold=0.8"
Braintrust::Eval.run(
  project: project_name,
  experiment: "parameters-demo",
  cases: [
    {input: "hello", expected: "HELLO!"},
    {input: "world", expected: "WORLD!"}
  ],
  task: task,
  scorers: [scorer],
  parameters: {"suffix" => "!", "threshold" => 0.8}
)

# --- Run again with different parameters ---
#
# Same task and scorer, different behavior.
puts "\nRunning again with parameters: suffix='?', threshold=0.5"
Braintrust::Eval.run(
  project: project_name,
  experiment: "parameters-demo-v2",
  cases: [
    {input: "hello", expected: "HELLO?"},
    {input: "world", expected: "WORLD?"}
  ],
  task: task,
  scorers: [scorer],
  parameters: {"suffix" => "?", "threshold" => 0.5}
)
