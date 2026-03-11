# frozen_string_literal: true

# Braintrust Rails Engine — mount example
#
# This file shows how to mount the Braintrust eval server as a Rails engine.
# The engine exposes the same endpoints as the standalone Rack server:
#   GET  /braintrust/       — health check
#   GET  /braintrust/list   — list registered evaluators
#   POST /braintrust/list   — list registered evaluators
#   POST /braintrust/eval   — run an evaluation (SSE stream)
#
# Requirements:
#   gem 'actionpack', '~> 8.0'
#   gem 'railties', '~> 8.0'
#   gem 'activesupport', '~> 8.0'

# ---------------------------------------------------------------------------
# config/initializers/braintrust_server.rb
# ---------------------------------------------------------------------------

require "braintrust/server/rails"

Braintrust::Contrib::Rails::Engine.configure do |config|
  # Register your evaluators by name. The Braintrust UI will discover them
  # via GET /braintrust/list and let you run them via POST /braintrust/eval.
  config.evaluators = {
    "my-classifier" => Braintrust::Eval::Evaluator.new(
      task: ->(input) { classify(input) },
      scorers: [
        Braintrust::Eval.scorer("accuracy") { |_input, expected, output|
          (output == expected) ? 1.0 : 0.0
        }
      ]
    )
  }

  # Auth strategy: :clerk_token (default) validates Braintrust session tokens.
  # Use :none for local development without authentication.
  config.auth = :clerk_token
end

# ---------------------------------------------------------------------------
# config/routes.rb
# ---------------------------------------------------------------------------

# Rails.application.routes.draw do
#   mount Braintrust::Contrib::Rails::Engine, at: "/braintrust"
# end

puts "Braintrust Rails Engine example — see comments for usage"
