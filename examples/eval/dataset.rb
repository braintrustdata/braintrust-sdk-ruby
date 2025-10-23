#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Running an evaluation against a dataset
#
# This example demonstrates:
# 1. Creating a dataset with test cases
# 2. Running an evaluation using the dataset
# 3. Different ways to specify datasets (string, hash with options)
#
# Usage:
#   ruby examples/eval/dataset.rb

require "bundler/setup"
require "braintrust"

# Initialize Braintrust with login (sets global state)
Braintrust.init(blocking_login: true)
api = Braintrust::API.new  # Uses global state

# Enable tracing to send spans to Braintrust
require "opentelemetry/sdk"
tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
Braintrust::Trace.enable(tracer_provider)
OpenTelemetry.tracer_provider = tracer_provider
at_exit { tracer_provider.shutdown }

# Project name
project_name = "ruby-sdk-examples"

# Create a dataset with test cases
dataset_name = "string-transform-#{Time.now.to_i}"
puts "Creating dataset '#{dataset_name}'..."

result = api.datasets.create(
  name: dataset_name,
  project_name: project_name,
  description: "Example dataset for string transformation evaluation"
)
dataset_id = result["dataset"]["id"]

# Insert test cases into the dataset
test_cases = [
  {input: "hello", expected: "HELLO"},
  {input: "world", expected: "WORLD"},
  {input: "ruby", expected: "RUBY"},
  {input: "braintrust", expected: "BRAINTRUST"}
]

api.datasets.insert(id: dataset_id, events: test_cases)

# Define task: simple string upcase
task = ->(input) do
  input.upcase
end

# Define scorer: exact match
scorer = Braintrust::Eval.scorer("exact_match") do |input, expected, output|
  (output == expected) ? 1.0 : 0.0
end

# Example 1: Run eval with dataset as string (uses same project)
puts "\n" + "=" * 60
puts "Example 1: Dataset as string (same project)"
puts "=" * 60

Braintrust::Eval.run(
  project: project_name,
  experiment: "dataset-eval-string",
  dataset: dataset_name,  # Simple string - fetches from same project
  task: task,
  scorers: [scorer]
)

# Example 2: Run eval with dataset as hash (explicit project)
puts "\n" + "=" * 60
puts "Example 2: Dataset as hash with explicit project"
puts "=" * 60

Braintrust::Eval.run(
  project: project_name,
  experiment: "dataset-eval-hash",
  dataset: {
    name: dataset_name,
    project: project_name  # Explicit project
  },
  task: task,
  scorers: [scorer]
)

# Example 3: Run eval with dataset by ID
puts "\n" + "=" * 60
puts "Example 3: Dataset by ID"
puts "=" * 60

Braintrust::Eval.run(
  project: project_name,
  experiment: "dataset-eval-id",
  dataset: {id: dataset_id},  # Fetch by ID
  task: task,
  scorers: [scorer]
)

# Example 4: Run eval with dataset limit
puts "\n" + "=" * 60
puts "Example 4: Dataset with record limit"
puts "=" * 60

Braintrust::Eval.run(
  project: project_name,
  experiment: "dataset-eval-limit",
  dataset: {
    name: dataset_name,
    project: project_name,
    limit: 2  # Only use first 2 records
  },
  task: task,
  scorers: [scorer]
)
