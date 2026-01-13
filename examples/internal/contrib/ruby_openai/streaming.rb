#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"

# Example: ruby-openai (alexrudall) streaming with Braintrust tracing
#
# This example demonstrates how to trace streaming OpenAI API calls
# using the ruby-openai gem. Shows the callback-based streaming pattern.
#
# Usage:
#   OPENAI_API_KEY=your-key bundle exec ruby examples/internal/contrib/ruby_openai/streaming.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  exit 1
end

Braintrust.init(blocking_login: true)
Braintrust.instrument!(:ruby_openai)

# ruby-openai uses access_token parameter
client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
tracer = OpenTelemetry.tracer_provider.tracer("ruby-openai-streaming-example")
root_span = nil

tracer.in_span("examples/internal/contrib/ruby_openai/streaming.rb") do |span|
  root_span = span

  # Pattern 1: Chat streaming with callback proc
  # Pass a proc to the stream parameter to receive chunks
  puts "=== Pattern 1: Chat streaming with callback ==="
  print "Assistant: "

  client.chat(
    parameters: {
      model: "gpt-4o-mini",
      max_tokens: 100,
      messages: [{role: "user", content: "Count from 1 to 5, one number per line."}],
      stream_options: {include_usage: true},
      stream: proc do |chunk, _bytesize|
        content = chunk.dig("choices", 0, "delta", "content")
        print content if content
      end
    }
  )
  puts "\n"

  # Pattern 2: Responses API streaming (if available)
  if client.respond_to?(:responses)
    puts "=== Pattern 2: Responses API streaming ==="
    print "Assistant: "

    client.responses.create(
      parameters: {
        model: "gpt-4o-mini",
        input: "Name 3 colors.",
        stream: proc do |chunk, _event|
          if chunk["type"] == "response.output_text.delta"
            print chunk["delta"]
          end
        end
      }
    )
    puts "\n"
  else
    puts "=== Pattern 2: Responses API (skipped - not available in this version) ==="
  end
end

puts "\nView this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

OpenTelemetry.tracer_provider.shutdown

puts "\nTrace sent to Braintrust!"
