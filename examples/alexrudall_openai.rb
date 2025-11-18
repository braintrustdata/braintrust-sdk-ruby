#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"

# Example: ruby-openai (alexrudall) chat completion with Braintrust tracing
#
# This example demonstrates how to automatically trace OpenAI API calls using
# the ruby-openai gem (by alexrudall) with Braintrust.
#
# Note: ruby-openai is an optional development dependency. To run this example:
#   1. Install ruby-openai: gem install ruby-openai
#   2. Run from the SDK root: ruby examples/alexrudall_openai.rb
#
# Usage:
#   OPENAI_API_KEY=your-openai-key ruby examples/alexrudall_openai.rb

# Check for API keys
unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  exit 1
end

Braintrust.init(blocking_login: true)

# Create OpenAI client (ruby-openai uses access_token parameter)
client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

# Wrap the client with Braintrust tracing
Braintrust::Trace::AlexRudall::RubyOpenAI.wrap(client)

# Create a root span to capture the entire operation
tracer = OpenTelemetry.tracer_provider.tracer("alexrudall-openai-example")
root_span = nil

# Make a chat completion request (automatically traced!)
puts "Sending chat completion request to OpenAI (using ruby-openai gem)..."
response = tracer.in_span("examples/alexrudall_openai.rb") do |span|
  root_span = span

  # ruby-openai uses: client.chat(parameters: {...})
  client.chat(
    parameters: {
      model: "gpt-4o-mini",
      messages: [
        {role: "system", content: "You are a helpful assistant."},
        {role: "user", content: "Say hello and tell me a short joke."}
      ],
      max_tokens: 100
    }
  )
end

# Print the response (ruby-openai returns a hash)
puts "\n✓ Response received!"
puts "\nAssistant: #{response.dig("choices", 0, "message", "content")}"

# Print usage stats
if response["usage"]
  puts "\nToken usage:"
  puts "  Prompt tokens: #{response["usage"]["prompt_tokens"]}"
  puts "  Completion tokens: #{response["usage"]["completion_tokens"]}"
  puts "  Total tokens: #{response["usage"]["total_tokens"]}"
end

# Print permalink to view this trace in Braintrust
puts "\n✓ View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust!"
