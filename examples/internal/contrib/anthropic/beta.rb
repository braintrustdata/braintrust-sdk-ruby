#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "anthropic"
require "opentelemetry/sdk"

# Example: Anthropic Beta API tracing with Braintrust
#
# This example demonstrates how to trace Anthropic's beta API calls,
# including the client.beta.messages endpoint which provides access to
# experimental features like structured outputs.
#
# Usage:
#   ANTHROPIC_API_KEY=your-key bundle exec ruby examples/internal/contrib/anthropic/beta.rb

# Check for API keys
unless ENV["ANTHROPIC_API_KEY"]
  puts "Error: ANTHROPIC_API_KEY environment variable is required"
  puts "Get your API key from: https://console.anthropic.com/"
  exit 1
end

# Instrument Anthropic (class-level, affects all clients)
# This automatically instruments both stable and beta APIs
Braintrust.init(blocking_login: true)

# Create Anthropic client
client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])

# Create a tracer instance
tracer = OpenTelemetry.tracer_provider.tracer("anthropic-beta-example")

puts "Braintrust Anthropic Beta API Examples"
puts "======================================="

root_span = nil

tracer.in_span("examples/internal/contrib/anthropic/beta.rb") do |span|
  root_span = span

  # --- Example 1: Basic beta API call ---
  puts "\n=== Example 1: Basic Beta API Call ==="
  tracer.in_span("beta-basic") do
    message = client.beta.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      messages: [
        {role: "user", content: "What is 2+2? Answer briefly."}
      ]
    )
    puts "  Claude: #{message.content[0].text}"
    puts "  Tokens: #{message.usage.input_tokens} in / #{message.usage.output_tokens} out"
  end

  # --- Example 2: Structured Outputs (JSON mode) ---
  puts "\n=== Example 2: Structured Outputs (JSON Mode) ==="
  tracer.in_span("beta-structured-outputs") do
    # Define the JSON schema for structured output
    output_format = {
      type: "json_schema",
      schema: {
        type: "object",
        properties: {
          name: {type: "string"},
          age: {type: "integer"},
          occupation: {type: "string"},
          hobbies: {
            type: "array",
            items: {type: "string"}
          }
        },
        required: ["name", "age", "occupation", "hobbies"],
        additionalProperties: false
      }
    }

    message = client.beta.messages.create(
      model: "claude-haiku-4-5",  # Cheapest model supporting structured outputs
      max_tokens: 200,
      betas: ["structured-outputs-2025-11-13"],
      output_format: output_format,
      messages: [
        {role: "user", content: "Generate a random fictional person with their details."}
      ]
    )

    # Parse and display the structured response
    json_response = message.content.first.text
    parsed = JSON.parse(json_response)

    puts "  Structured Output:"
    puts "    Name: #{parsed["name"]}"
    puts "    Age: #{parsed["age"]}"
    puts "    Occupation: #{parsed["occupation"]}"
    puts "    Hobbies: #{parsed["hobbies"].join(", ")}"
    puts "  Tokens: #{message.usage.input_tokens} in / #{message.usage.output_tokens} out"
  end
end

puts "\n=== Examples Complete ==="
puts "View trace: #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown
