#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"

# Example: OpenAI streaming with Braintrust tracing
#
# This example demonstrates how to trace streaming OpenAI API calls.
# Shows two streaming patterns:
#   1. Chat completions with stream_raw
#   2. Responses API with stream
#
# Usage:
#   OPENAI_API_KEY=your-key bundle exec ruby examples/internal/contrib/openai/streaming.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  exit 1
end

Braintrust.init(blocking_login: true)
Braintrust.instrument!(:openai)

client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])
tracer = OpenTelemetry.tracer_provider.tracer("openai-streaming-example")
root_span = nil

tracer.in_span("examples/internal/contrib/openai/streaming.rb") do |span|
  root_span = span

  # Pattern 1: Chat completions streaming with stream_raw
  # Returns an iterator that yields chunks
  puts "=== Pattern 1: Chat completions with stream_raw ==="
  print "Assistant: "

  stream = client.chat.completions.stream_raw(
    model: "gpt-4o-mini",
    max_tokens: 100,
    messages: [{role: "user", content: "Count from 1 to 5, one number per line."}],
    stream_options: {include_usage: true}
  )

  stream.each do |chunk|
    if chunk.choices&.first&.delta&.content
      print chunk.choices.first.delta.content
    end
  end
  puts "\n"

  # Pattern 2: Responses API streaming
  # Returns an iterator that yields events
  puts "=== Pattern 2: Responses API with stream ==="
  print "Assistant: "

  stream = client.responses.stream(
    model: "gpt-4o-mini",
    input: "Name 3 colors."
  )

  stream.each do |event|
    if event.type == :"response.output_text.delta"
      print event.delta
    end
  end
  puts "\n"
end

puts "\nView this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

OpenTelemetry.tracer_provider.shutdown

puts "\nTrace sent to Braintrust!"
