#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "ruby_llm"
require "opentelemetry/sdk"

# Example: RubyLLM chat with Braintrust tracing
#
# This example demonstrates how to automatically trace RubyLLM API calls with Braintrust.
#
# Usage:
#   OPENAI_API_KEY=your-openai-key bundle exec ruby examples/ruby_llm.rb

# Check for API keys
unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  exit 1
end

Braintrust.init(blocking_login: true)

# Configure RubyLLM
RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
end

# Create a chat instance
chat = RubyLLM.chat(model: "gpt-4o-mini")

# Wrap the chat instance with Braintrust tracing
Braintrust::Trace::RubyLLM.wrap(chat)

# Create a root span to capture the entire operation
tracer = OpenTelemetry.tracer_provider.tracer("ruby_llm-example")
root_span = nil

# Make a chat request (automatically traced!)
puts "Sending chat request to RubyLLM..."
response = tracer.in_span("examples/ruby_llm.rb") do |span|
  root_span = span

  chat.ask("What is the capital of France?")
end

# Print the response
puts "\n✓ Response received!"
puts "\nAssistant: #{response.content}"

# Print usage stats
puts "\nToken usage:"
puts "  Input tokens: #{response.to_h[:input_tokens]}"
puts "  Output tokens: #{response.to_h[:output_tokens]}"

# Print permalink to view this trace in Braintrust
puts "\n✓ View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust!"
