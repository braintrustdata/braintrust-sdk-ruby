#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"

# Usage:
#   OPENAI_API_KEY=your-openai-key bundle exec appraisal openai ruby examples/contrib/openai.rb

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
client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])

# Make a chat completion request (automatically traced!)
client.chat.completions.create(
  messages: [
    {role: "system", content: "You are a helpful assistant."},
    {role: "user", content: "Say hello and tell me a short joke."}
  ],
  model: "gpt-4o-mini",
  max_tokens: 100
)

# Print permalink to view this trace in Braintrust
puts "\n View this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
#
# NOTE: shutdown is only necessary for this short-lived example.
#       In most production apps, you can omit this.
OpenTelemetry.tracer_provider.shutdown
