#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "opentelemetry/sdk"

# Example: Evals with Errors
#
# This example demonstrates how Braintrust handles errors in evals:
# 1. Task that raises an error
# 2. Task that succeeds
# 3. Scorer that raises an error
#
# The eval continues despite errors and reports them in the results.
#
# Usage:
#   BRAINTRUST_API_KEY=key bundle exec ruby examples/internal/evals-with-errors.rb

unless ENV["BRAINTRUST_API_KEY"]
  puts "Error: BRAINTRUST_API_KEY environment variable is required"
  exit 1
end

# Initialize Braintrust with blocking login
Braintrust.init(blocking_login: true)

# Create OpenTelemetry TracerProvider
tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

# Enable Braintrust tracing
Braintrust::Trace.enable(tracer_provider)

# Set as global provider
OpenTelemetry.tracer_provider = tracer_provider

puts "Evals with Errors Example"
puts "=" * 60
puts "This example demonstrates error handling in tasks and scorers"
puts

# Task that fails for certain inputs
def risky_task(input)
  case input
  when "trigger_error"
    raise StandardError, "Task failed: input triggered an error!"
  when "divide_by_zero"
    result = 42 / 0 # ZeroDivisionError
    "Result: #{result}"
  when "timeout"
    raise Timeout::Error, "Task timed out!"
  else
    "Success: processed '#{input}'"
  end
end

# Scorer that always succeeds
exact_match_scorer = Braintrust::Eval.scorer("exact_match") do |input, expected, output|
  next 0.0 if output.nil?
  (output == expected) ? 1.0 : 0.0
end

# Scorer that fails for certain cases
failing_scorer = Braintrust::Eval.scorer("failing_scorer") do |input, expected, output, metadata|
  # This scorer intentionally fails on certain conditions
  if metadata && metadata[:fail_scorer]
    raise "Scorer failed: metadata indicated failure!"
  end

  # Check for nil output (might happen if task failed)
  return 0.0 if output.nil?

  # For demonstration, fail on specific output patterns
  if output.include?("trigger")
    raise ArgumentError, "Scorer cannot handle outputs containing 'trigger'"
  end

  # Otherwise, check if output contains "Success"
  output.include?("Success") ? 1.0 : 0.0
end

# Scorer that handles errors gracefully
robust_scorer = Braintrust::Eval.scorer("robust_scorer") do |input, expected, output, metadata|
  # Handle nil output gracefully
  return 0.0 if output.nil?

  begin
    # Try to score
    score = output.downcase.include?("success") ? 1.0 : 0.0
    score
  rescue => e
    # Log the error but don't fail
    puts "Robust scorer caught error: #{e.message}"
    0.0
  end
end

# Test cases demonstrating different error scenarios
test_cases = [
  # Case 1: Task succeeds, all scorers succeed
  {
    input: "normal_input",
    expected: "Success: processed 'normal_input'",
    tags: ["success", "baseline"]
  },

  # Case 2: Task succeeds, all scorers succeed
  {
    input: "another_good_input",
    expected: "Success: processed 'another_good_input'",
    tags: ["success", "baseline"]
  },

  # Case 3: Task fails with StandardError
  {
    input: "trigger_error",
    expected: "Success: processed 'trigger_error'",
    tags: ["error", "task_failure", "standard_error"]
  },

  # Case 4: Task fails with ZeroDivisionError
  {
    input: "divide_by_zero",
    expected: "Result: something",
    tags: ["error", "task_failure", "zero_division"]
  },

  # Case 5: Task fails with Timeout::Error
  {
    input: "timeout",
    expected: "Success: processed 'timeout'",
    tags: ["error", "task_failure", "timeout"]
  },

  # Case 6: Task succeeds, but scorer fails due to metadata
  {
    input: "good_input_but_scorer_fails",
    expected: "Success: processed 'good_input_but_scorer_fails'",
    metadata: {fail_scorer: true},
    tags: ["error", "scorer_failure", "metadata_triggered"]
  },

  # Case 7: Task succeeds, multiple scorers, mix of pass/fail
  {
    input: "final_success",
    expected: "Success: processed 'final_success'",
    tags: ["success", "mixed_scorers"]
  }
]

# Run the evaluation
puts "Running evaluation with error scenarios..."
puts "Cases: #{test_cases.length}"
puts "Scorers: 3 (exact_match, failing_scorer, robust_scorer)"
puts

result = Braintrust::Eval.run(
  project: "ruby-sdk-examples",
  experiment: "evals-with-errors",

  cases: test_cases,

  # Task that may fail
  task: ->(input) { risky_task(input) },

  # Multiple scorers - some may fail
  scorers: [
    exact_match_scorer,
    failing_scorer,
    robust_scorer
  ],

  # Run with some parallelism
  parallelism: 2,

  # Tags for the experiment
  tags: ["error-handling", "example", "internal"],

  # Metadata for the experiment
  metadata: {
    description: "Demonstrates error handling in tasks and scorers",
    error_scenarios: [
      "task_standard_error",
      "task_zero_division",
      "task_timeout",
      "scorer_metadata_triggered",
      "scorer_output_pattern"
    ]
  }
)

# Print results
puts "\n" + "=" * 60
puts "Evaluation Complete!"
puts "=" * 60

puts "\nExperiment: #{result.experiment_name}"
puts "Project ID: #{result.project_id}"
puts "Duration: #{result.duration.round(2)}s"

# Note: result.success? returns true even with errors in individual cases
# The eval system continues despite errors and reports them
puts "\nOverall Status: #{result.success? ? "✓ Completed" : "✗ Failed"}"

puts "\nView detailed results (including errors) at:"
puts "  #{result.permalink}"

# Show errors if any
if result.errors.any?
  puts "\n⚠ Errors encountered during evaluation (#{result.errors.length}):"
  result.errors.each_with_index do |error, i|
    puts "\n  #{i + 1}. #{error}"
  end

  puts "\nNote: Errors in individual cases/scorers are captured and reported."
  puts "The eval continues despite errors to maximize data collection."
end

if result.success?
  puts "\n✓ Evaluation completed successfully!"
  puts "  (Some individual cases or scorers may have failed - check results above)"
end

# Shutdown to flush spans to Braintrust
tracer_provider.shutdown
