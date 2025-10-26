#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"

# Example: Auto-instrumentation for OpenAI
#
# This example demonstrates automatic instrumentation that eliminates the need
# to manually wrap each client.
#
# Usage:
#   OPENAI_API_KEY=your-openai-key bundle exec ruby examples/autoinstrument.rb

# Check for API keys
unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  exit 1
end

puts "=== Auto-Instrumentation Example ==="
puts

# Enable auto-instrumentation for all supported libraries
puts "Initializing Braintrust with auto-instrumentation enabled..."
Braintrust.init(
  blocking_login: true,
  autoinstrument: {enabled: true}
)
puts "✓ Auto-instrumentation enabled for: OpenAI, Anthropic"
puts

# Create OpenAI client AFTER initialization
# This client is automatically wrapped - no manual wrap() call needed!
puts "Creating OpenAI client..."
client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])
puts "✓ Client created and automatically instrumented"
puts

# Create a root span to organize the trace
tracer = OpenTelemetry.tracer_provider.tracer("autoinstrument-example")
root_span = nil

# Make a chat completion request - automatically traced!
puts "Sending request to OpenAI (automatically traced)..."
response = tracer.in_span("examples/autoinstrument.rb") do |span|
  root_span = span

  client.chat.completions.create(
    messages: [
      {role: "system", content: "You are a helpful assistant."},
      {role: "user", content: "In one sentence, what is auto-instrumentation?"}
    ],
    model: "gpt-4o-mini",
    max_tokens: 100
  )
end

# Print the response
puts "\n✓ Response received!"
puts "\nAssistant: #{response.choices[0].message.content}"

# Print usage stats
puts "\nToken usage:"
puts "  Prompt tokens: #{response.usage.prompt_tokens}"
puts "  Completion tokens: #{response.usage.completion_tokens}"
puts "  Total tokens: #{response.usage.total_tokens}"

# Print permalink to view this trace in Braintrust
puts "\n✓ View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust!"
puts
puts "Key benefits of auto-instrumentation:"
puts "  • No need to call wrap() on each client"
puts "  • Works for all clients created after init"
puts "  • Can selectively enable/disable per library"
puts "  • Prevents double-wrapping automatically"
