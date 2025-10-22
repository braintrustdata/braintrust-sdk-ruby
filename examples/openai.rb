#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"

# Example: OpenAI chat completion with Braintrust tracing
#
# This example demonstrates how to automatically trace OpenAI API calls with Braintrust.
#
# Note: The openai gem is a development dependency. To run this example:
#   1. Install dependencies: bundle install
#   2. Run from the SDK root: bundle exec ruby examples/openai.rb
#
# Usage:
#   BRAINTRUST_API_KEY=your-bt-key OPENAI_API_KEY=your-openai-key bundle exec ruby examples/openai.rb
#
# Optional: Set a default project for traces
#   BRAINTRUST_DEFAULT_PROJECT=project_name:my-project bundle exec ruby examples/openai.rb

# Check for API keys
unless ENV["BRAINTRUST_API_KEY"]
  puts "Error: BRAINTRUST_API_KEY environment variable is required"
  puts "Get your API key from: https://www.braintrust.dev/app/settings"
  exit 1
end

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  exit 1
end

# Initialize Braintrust with blocking login to ensure org name is available for permalinks
Braintrust.init(blocking_login: true)

# Create OpenTelemetry TracerProvider
tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new

# Enable Braintrust tracing
Braintrust::Trace.enable(tracer_provider)

# Set as global provider
OpenTelemetry.tracer_provider = tracer_provider

# Create OpenAI client
client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])

# Wrap the client with Braintrust tracing
# This automatically creates spans for all chat completion requests
Braintrust::Trace::OpenAI.wrap(client, tracer_provider: tracer_provider)

# Create a root span to capture the entire operation
tracer = tracer_provider.tracer("openai-example")
root_span = nil

# Make a chat completion request (automatically traced!)
puts "Sending chat completion request to OpenAI..."
response = tracer.in_span("examples/openai.rb") do |span|
  root_span = span

  client.chat.completions.create(
    messages: [
      {role: "system", content: "You are a helpful assistant."},
      {role: "user", content: "Say hello and tell me a short joke."}
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
tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust!"
