#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"

# Usage:
#   OPENAI_API_KEY=your-openai-key bundle exec appraisal ruby-openai ruby examples/contrib/ruby-openai.rb

# Check for API keys
unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  exit 1
end

# Initialize Braintrust (with blocking login)
#
# NOTE: blocking_login is only necessary for this short-lived example.
#       In most production apps, you can omit this.
Braintrust.init(blocking_login: true)

# Create OpenAI client
client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

# Get a tracer and wrap the API call in a span
tracer = OpenTelemetry.tracer_provider.tracer("ruby-openai-example")

root_span = nil
tracer.in_span("examples/contrib/ruby-openai.rb") do |span|
  root_span = span

  # Make a chat request (automatically traced!)
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

# Print permalink to view this trace in Braintrust
puts "\nView this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
#
# NOTE: shutdown is only necessary for this short-lived example.
#       In most production apps, you can omit this.
OpenTelemetry.tracer_provider.shutdown
