#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "anthropic"
require "opentelemetry/sdk"

# Example: Instance-level Anthropic instrumentation
#
# This shows how to instrument a specific client instance rather than
# all Anthropic clients globally.
#
# Usage:
#   ANTHROPIC_API_KEY=your-key bundle exec ruby examples/internal/contrib/anthropic/instance.rb

unless ENV["ANTHROPIC_API_KEY"]
  puts "Error: ANTHROPIC_API_KEY environment variable is required"
  exit 1
end

Braintrust.init(blocking_login: true)

# Create two client instances
client_traced = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
client_untraced = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])

# Only instrument one of them
Braintrust.instrument!(:anthropic, target: client_traced)

tracer = OpenTelemetry.tracer_provider.tracer("anthropic-example")
root_span = nil

tracer.in_span("examples/internal/contrib/anthropic/instance.rb") do |span|
  root_span = span

  puts "Calling traced client..."
  response1 = client_traced.messages.create(
    model: "claude-3-haiku-20240307",
    max_tokens: 10,
    messages: [{role: "user", content: "Say 'traced'"}]
  )
  puts "Traced response: #{response1.content[0].text}"

  puts "\nCalling untraced client..."
  response2 = client_untraced.messages.create(
    model: "claude-3-haiku-20240307",
    max_tokens: 10,
    messages: [{role: "user", content: "Say 'untraced'"}]
  )
  puts "Untraced response: #{response2.content[0].text}"
end

puts "\nView trace: #{Braintrust::Trace.permalink(root_span)}"
puts "(Only the first client call should have an anthropic.messages span)"

OpenTelemetry.tracer_provider.shutdown
