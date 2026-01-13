#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "anthropic"
require "opentelemetry/sdk"

# Example: Anthropic streaming with Braintrust tracing
#
# This example demonstrates how to trace streaming Anthropic API calls.
# Shows two different streaming patterns:
#   1. Iterator-based streaming with .each (full event access)
#   2. Text-only streaming with .text (simplified)
#
# Usage:
#   ANTHROPIC_API_KEY=your-key bundle exec ruby examples/internal/contrib/anthropic/streaming.rb

unless ENV["ANTHROPIC_API_KEY"]
  puts "Error: ANTHROPIC_API_KEY environment variable is required"
  puts "Get your API key from: https://console.anthropic.com/"
  exit 1
end

Braintrust.init(blocking_login: true)
Braintrust.instrument!(:anthropic)

client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
tracer = OpenTelemetry.tracer_provider.tracer("anthropic-streaming-example")
root_span = nil

tracer.in_span("examples/internal/contrib/anthropic/streaming.rb") do |span|
  root_span = span

  # Pattern 1: Iterator-based streaming with .each
  # Returns a MessageStream, iterate to get individual events
  puts "=== Pattern 1: Iterator with .each ==="
  print "Claude: "

  stream = client.messages.stream(
    model: "claude-3-haiku-20240307",
    max_tokens: 100,
    messages: [{role: "user", content: "Count from 1 to 5, one number per line."}]
  )

  stream.each do |event|
    if event.type == :content_block_delta && event.delta.respond_to?(:text)
      print event.delta.text
    end
  end
  puts "\n"

  # Pattern 2: Text-only streaming with .text
  # Returns an Enumerator that yields only text chunks (simpler)
  puts "=== Pattern 2: Text-only with .text ==="
  print "Claude: "

  stream = client.messages.stream(
    model: "claude-3-haiku-20240307",
    max_tokens: 100,
    messages: [{role: "user", content: "Name 3 colors."}]
  )

  stream.text.each do |text_chunk|
    print text_chunk
  end
  puts "\n"
end

puts "\nView this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

OpenTelemetry.tracer_provider.shutdown

puts "\nTrace sent to Braintrust!"
