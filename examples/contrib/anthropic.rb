#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "anthropic"
require "opentelemetry/sdk"

# Usage:
#   ANTHROPIC_API_KEY=your-key bundle exec appraisal anthropic ruby examples/contrib/anthropic.rb

# Check for API keys
unless ENV["ANTHROPIC_API_KEY"]
  puts "Error: ANTHROPIC_API_KEY environment variable is required"
  puts "Get your API key from: https://console.anthropic.com/"
  exit 1
end

# Initialize Braintrust (with blocking login)
#
# NOTE: blocking_login is only necessary for this short-lived example.
#       In most production apps, you can omit this.
Braintrust.init(blocking_login: true)

# Create Anthropic client
client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])

# Make a message request (automatically traced!)
client.messages.create(
  model: "claude-3-haiku-20240307",
  max_tokens: 100,
  system: "You are a helpful assistant.",
  messages: [
    {role: "user", content: "Say hello and tell me a short joke."}
  ]
)

# Print permalink to view this trace in Braintrust
puts "\n View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
#
# NOTE: shutdown is only necessary for this short-lived example.
#       In most production apps, you can omit this.
OpenTelemetry.tracer_provider.shutdown
