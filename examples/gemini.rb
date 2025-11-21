#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "gemini-ai"
require "opentelemetry/sdk"

# Example: Gemini content generation with Braintrust tracing
#
# This example demonstrates how to automatically trace Gemini API calls with Braintrust.
#
# Usage:
#   GOOGLE_API_KEY=your-key bundle exec ruby examples/gemini.rb

# Check for API keys
unless ENV["GOOGLE_API_KEY"]
  puts "Error: GOOGLE_API_KEY environment variable is required"
  puts "Get your API key from: https://makersuite.google.com/app/apikey"
  exit 1
end

Braintrust.init(blocking_login: true)

# Create Gemini client
client = Gemini.new(
  credentials: {
    service: "generative-language-api",
    api_key: ENV["GOOGLE_API_KEY"]
  },
  options: {model: "gemini-1.5-flash"}
)

# Wrap the client with Braintrust tracing
Braintrust::Trace::Gemini.wrap(client)

# Create a root span to capture the entire operation
tracer = OpenTelemetry.tracer_provider.tracer("gemini-example")
root_span = nil

# Make a generate_content request (automatically traced!)
puts "Sending request to Gemini..."
result = tracer.in_span("examples/gemini.rb") do |span|
  root_span = span

  client.generate_content({
    contents: {
      role: "user",
      parts: {text: "Say hello and tell me a short joke."}
    }
  })
end

# Extract the response text
response_text = result[0]["candidates"][0]["content"]["parts"][0]["text"]

# Print the response
puts "\n✓ Response received!"
puts "\nGemini: #{response_text}"

# Print usage stats
usage = result[0]["usageMetadata"]
if usage
  puts "\nToken usage:"
  puts "  Prompt tokens: #{usage["promptTokenCount"]}"
  puts "  Candidates tokens: #{usage["candidatesTokenCount"]}"
  puts "  Total tokens: #{usage["totalTokenCount"]}"
end

# Print permalink to view this trace in Braintrust
puts "\n✓ View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust!"
