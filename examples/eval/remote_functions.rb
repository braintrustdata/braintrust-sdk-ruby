#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using remote functions (server-side prompts) in evaluations
#
# This example demonstrates how to:
# 1. Create a remote task function (prompt) on the Braintrust server
# 2. Create a remote scorer function with LLM classifier and choices
# 3. Use both remote task and scorer in Eval.run
#
# Benefits of remote functions:
# - Centralized prompt management
# - Version control for prompts
# - No need to deploy prompt changes with code
# - Consistent prompt execution across environments
# - Remote scorers use choice_scores for deterministic scoring

require "bundler/setup"
require "braintrust"
require "braintrust/eval"
require "braintrust/eval/functions"

# Initialize Braintrust with tracing enabled (default)
Braintrust.init

project_name = "ruby-sdk-examples"

# First, let's create remote functions (task + scorer) on the server
# In practice, you would create these once via the UI or API
puts "Creating remote functions..."

api = Braintrust::API.new
function_slug = "food-classifier-#{Time.now.to_i}"

api.functions.create(
  project_name: project_name,
  slug: function_slug,
  function_data: {type: "prompt"},
  prompt_data: {
    prompt: {
      type: "chat",
      messages: [
        {
          role: "system",
          content: "You are a food classifier. Classify the input as 'fruit' or 'vegetable'. Return ONLY the classification, nothing else."
        },
        {
          role: "user",
          content: "Classify: {{input}}"
        }
      ]
    },
    options: {
      model: "gpt-4o-mini",
      params: {temperature: 0}
    }
  }
)

puts "Created task function: #{function_slug}"

# Create a remote scorer function (uses LLM classifier with choices)
scorer_slug = "classification-scorer-#{Time.now.to_i}"
api.functions.create(
  project_name: project_name,
  slug: scorer_slug,
  function_data: {type: "prompt"},
  prompt_data: {
    parser: {
      type: "llm_classifier",
      use_cot: true,
      choice_scores: {
        "correct" => 1.0,
        "incorrect" => 0.0
      }
    },
    prompt: {
      type: "chat",
      messages: [
        {
          role: "system",
          content: "You are a scorer evaluating food classifications."
        },
        {
          role: "user",
          content: "Expected: {{expected}}\nActual output: {{output}}\n\nDoes the output correctly classify the food? Choose 'correct' if it matches (case-insensitive), otherwise 'incorrect'."
        }
      ]
    },
    options: {
      model: "gpt-4o-mini",
      params: {temperature: 0, use_cache: true}
    }
  }
)
puts "Created scorer function: #{scorer_slug}"

# Now use the remote functions in Eval.run
puts "\nRunning evaluation with remote functions..."

# Get references to the remote functions
task = Braintrust::Eval::Functions.task(
  project: project_name,
  slug: function_slug
)

remote_scorer = Braintrust::Eval::Functions.scorer(
  project: project_name,
  slug: scorer_slug
)

# Define test cases
cases = [
  {input: "apple", expected: "fruit"},
  {input: "banana", expected: "fruit"},
  {input: "carrot", expected: "vegetable"},
  {input: "broccoli", expected: "vegetable"}
]

# Run the evaluation
# Both the task AND scorer will execute on the Braintrust server, not locally
Braintrust::Eval.run(
  project: project_name,
  experiment: "remote-function-demo",
  cases: cases,
  task: task,
  scorers: [remote_scorer]
)

# Flush all spans to ensure they're exported
OpenTelemetry.tracer_provider.shutdown
