#!/usr/bin/env ruby
# frozen_string_literal: true

# Dev Server - Basic Example
#
# This example demonstrates how to set up a dev server for remote evals
# that receives evaluation requests from the Braintrust web UI.
#
# 1. Define evaluators (subclass or inline)
# 2. Pass them to the Rack app and start serving
#
# Usage:
#   # Start the server (requires rack and a Rack-compatible server like puma):
#   bundle exec rackup examples/server/eval.ru -p 8300 -o 0.0.0.0

require "bundler/setup"
require "braintrust"
require "braintrust/server"

# --- Step 1: Define evaluators ---
#
# Evaluators define the task (the code under evaluation) and local scorers.
# They can reference any application code — models, services, database queries, etc.

# Subclass pattern: override #task and #scorers methods.
class FoodClassifier < Braintrust::Eval::Evaluator
  def task
    ->(input) {
      case input.to_s.downcase
      when /apple|banana|orange|grape/ then "fruit"
      when /carrot|broccoli|spinach/ then "vegetable"
      else "unknown"
      end
    }
  end

  def scorers
    [
      Braintrust::Eval.scorer("exact_match") do |input, expected, output|
        (output == expected) ? 1.0 : 0.0
      end
    ]
  end
end

# Inline pattern: pass task and scorers as constructor arguments.
text_summarizer = Braintrust::Eval::Evaluator.new(
  task: ->(input) {
    words = input.to_s.split
    words.first(10).join(" ") + ((words.length > 10) ? "..." : "")
  },
  scorers: [
    Braintrust::Eval.scorer("length_check") do |input, expected, output|
      (output.to_s.length < input.to_s.length) ? 1.0 : 0.0
    end
  ],
  parameters: {
    "max_length" => {type: "number", default: 100, description: "Maximum summary length"}
  }
)

# --- Step 2: Initialize Braintrust tracing ---
#
# Call Braintrust.init before building the Rack app to enable span export.
# This ensures experiments appear in the Braintrust UI with their spans.
# Without this, evals still run but experiment spans won't be recorded.
#
# blocking_login: true ensures the SDK resolves the org-specific API
# endpoint before the server starts accepting requests.
#
# Requires BRAINTRUST_API_KEY env var (or pass api_key: directly).
Braintrust.init(blocking_login: true)

# --- Step 3: Start the server ---
#
# Mount the Rack app. The server handles:
# - GET  /      → health check
# - POST /list  → list evaluators
# - POST /eval  → execute an evaluation (SSE streaming response)
# - OPTIONS *   → CORS preflight

run Braintrust::Server::Rack.app(
  evaluators: {
    "food-classifier" => FoodClassifier.new,
    "text-summarizer" => text_summarizer
  }
)
