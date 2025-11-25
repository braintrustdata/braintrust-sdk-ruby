#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "anthropic"
require "opentelemetry/sdk"

# Example: Anthropic message creation with Braintrust tracing
#
# This example demonstrates how to automatically trace Anthropic API calls with Braintrust.
#
# Usage:
#   ANTHROPIC_API_KEY=your-key bundle exec ruby examples/anthropic.rb

# Check for API keys
unless ENV["ANTHROPIC_API_KEY"]
  puts "Error: ANTHROPIC_API_KEY environment variable is required"
  puts "Get your API key from: https://console.anthropic.com/"
  exit 1
end

Braintrust.init(blocking_login: true)

# Create Anthropic client
client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])

# Wrap the client with Braintrust tracing
Braintrust::Trace::Anthropic.wrap(client)

# Create a root span to capture the entire operation
tracer = OpenTelemetry.tracer_provider.tracer("anthropic-example")
root_span = nil

# Make a message request (automatically traced!)
puts "Sending message request to Anthropic..."
message = tracer.in_span("examples/anthropic.rb") do |span|
  root_span = span

  client.messages.create(
    model: "claude-3-haiku-20240307",
    max_tokens: 100,
    system: "You are a helpful assistant.",
    messages: [
      {role: "user", content: "Say hello and tell me a short joke."}
    ]
  )
end

# Print the response
puts "\n✓ Response received!"
puts "\nClaude: #{message.content[0].text}"

# Print usage stats
puts "\nToken usage:"
puts "  Input tokens: #{message.usage.input_tokens}"
puts "  Output tokens: #{message.usage.output_tokens}"

# Print permalink to view this trace in Braintrust
puts "\n✓ View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust!"
