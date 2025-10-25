#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "opentelemetry/sdk"

# Example: Food Classification Eval
#
# This example demonstrates the Eval API for running evaluations:
# 1. Define test cases (input + expected output)
# 2. Define a task (the code being evaluated)
# 3. Define scorers (how to judge the output)
# 4. Run the eval with parallelism
# 5. Inspect the results
#
# Usage:
#   bundle exec ruby examples/eval.rb

Braintrust.init

# Simple food classifier (the code being evaluated)
# In a real scenario, this would call your model/API
def classify_food(input)
  # Simple rule-based classifier for demo
  fruit = %w[apple banana strawberry orange grape mango]
  vegetable = %w[carrot broccoli spinach potato tomato cucumber]

  input_lower = input.downcase
  return "fruit" if fruit.any? { |f| input_lower.include?(f) }
  return "vegetable" if vegetable.any? { |v| input_lower.include?(v) }
  "unknown"
end

# Example of a class-based scorer (reusable)
class FuzzyMatchScorer
  def name
    "fuzzy_match"
  end

  def call(input, expected, output, metadata = {})
    threshold = metadata[:threshold] || 0.8

    # Simple fuzzy matching (in real scenario, use Levenshtein distance)
    similarity = if output == expected
      1.0
    elsif output.downcase.include?(expected.downcase) || expected.downcase.include?(output.downcase)
      0.7
    else
      0.0
    end

    (similarity >= threshold) ? 1.0 : 0.0
  end
end

# Example of a lambda scorer (can pass directly without wrapping)
length_match = ->(input, expected, output) {
  # Score based on whether output has correct length
  (output.length == expected.length) ? 1.0 : 0.0
}

# Run the evaluation
Braintrust::Eval.run(
  # Required: Project and experiment
  project: "ruby-sdk-examples",
  experiment: "food-classifier-eval",

  # Required: Test cases
  # Each case has input, expected output, and optional tags/metadata
  cases: [
    {input: "apple", expected: "fruit"},
    {input: "carrot", expected: "vegetable"},
    {input: "banana", expected: "fruit", tags: ["tropical"]},
    {input: "broccoli", expected: "vegetable"},
    {input: "strawberry", expected: "fruit", tags: ["berry"]},
    {input: "potato", expected: "vegetable"},
    {input: "orange", expected: "fruit", tags: ["citrus"]},
    {input: "spinach", expected: "vegetable", tags: ["leafy"]}
  ],

  # Required: Task (callable)
  # Can be a proc, lambda, method reference, or object with .call
  task: ->(input) { classify_food(input) },

  # Required: Scorers (array)
  # Scorers evaluate the quality of the output
  scorers: [
    # Simple inline scorer - exact match
    # Takes 3 params: input, expected, output
    Braintrust::Eval.scorer("exact_match") { |input, expected, output|
      (output == expected) ? 1.0 : 0.0
    },

    # Advanced inline scorer - with metadata
    # Takes 4 params: input, expected, output, metadata
    Braintrust::Eval.scorer("case_insensitive_match") { |input, expected, output, metadata|
      (output.downcase == expected.downcase) ? 1.0 : 0.0
    },

    # Class-based scorer (reusable)
    FuzzyMatchScorer.new,

    # Lambda scorer (auto-named as "scorer")
    # Just pass the lambda directly - no wrapper needed!
    length_match
  ],

  # Optional: Run 3 cases in parallel
  parallelism: 3,

  # Optional: Tags for the experiment
  tags: ["example", "food-classification", "v1"],

  # Optional: Metadata for the experiment
  metadata: {
    description: "Food classification eval example",
    version: "1.0.0"
  }
)

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown
