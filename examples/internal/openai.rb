#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"
require "json"

# Internal example: Comprehensive OpenAI features with Braintrust tracing
#
# This example demonstrates all major OpenAI chat completion features:
# 1. Vision (image understanding)
# 2. Tool/function calling
# 3. Streaming responses
# 4. Reasoning models (o1-mini)
#
# Usage:
#   BRAINTRUST_API_KEY=key OPENAI_API_KEY=key bundle exec ruby examples/internal/openai.rb

unless ENV["BRAINTRUST_API_KEY"]
  puts "Error: BRAINTRUST_API_KEY environment variable is required"
  exit 1
end

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

Braintrust.init(blocking_login: true)

# Get a tracer for this example
tracer = OpenTelemetry.tracer_provider.tracer("openai-comprehensive-example")

# Create OpenAI client and wrap it
client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])
Braintrust::Trace::OpenAI.wrap(client)

puts "OpenAI Comprehensive Features Example"
puts "=" * 50

# Wrap all examples under a single parent trace
root_span = nil
tracer.in_span("examples/internal/openai.rb") do |span|
  root_span = span
  # Example 1: Vision - Image Understanding
  puts "\n1. Vision (Image Understanding)"
  puts "-" * 50
  tracer.in_span("example-vision") do
    response = client.chat.completions.create(
      model: "gpt-4o-mini",
      messages: [
        {
          role: "user",
          content: [
            {type: "text", text: "What's in this image?"},
            {
              type: "image_url",
              image_url: {
                url: "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/320px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"
              }
            }
          ]
        }
      ],
      max_tokens: 100
    )
    puts "✓ Vision response: #{response.choices[0].message.content[0..100]}..."
    puts "  Tokens: #{response.usage.total_tokens}"
  end

  # Example 2: Tool/Function Calling
  puts "\n2. Tool/Function Calling"
  puts "-" * 50
  tracer.in_span("example-tools") do
    response = client.chat.completions.create(
      model: "gpt-4o-mini",
      messages: [
        {role: "user", content: "What's the weather like in San Francisco?"}
      ],
      tools: [
        {
          type: "function",
          function: {
            name: "get_weather",
            description: "Get the current weather in a given location",
            parameters: {
              type: "object",
              properties: {
                location: {
                  type: "string",
                  description: "The city and state, e.g. San Francisco, CA"
                },
                unit: {
                  type: "string",
                  enum: ["celsius", "fahrenheit"]
                }
              },
              required: ["location"]
            }
          }
        }
      ],
      tool_choice: "auto",
      max_tokens: 100
    )

    message = response.choices[0].message
    if message.tool_calls&.any?
      tool_call = message.tool_calls[0]
      puts "✓ Tool called: #{tool_call.function.name}"
      puts "  Arguments: #{tool_call.function.arguments}"
    else
      puts "✓ Response: #{message.content}"
    end
    puts "  Tokens: #{response.usage.total_tokens}"
  end

  # Example 3: Streaming (TODO: requires wrapper support for stream_raw)
  # Skipping for now - requires different API in OpenAI gem
  puts "\n3. Streaming Response"
  puts "-" * 50
  puts "⊘ Skipped: Streaming requires wrapper updates (stream_raw API)"

  # Example 4: Reasoning Model (o1-mini)
  puts "\n4. Reasoning Model (o1-mini)"
  puts "-" * 50
  tracer.in_span("example-reasoning") do
    response = client.chat.completions.create(
      model: "o1-mini",
      messages: [
        {
          role: "user",
          content: "If I have 3 apples and buy 2 more, then give away 1, how many do I have?"
        }
      ]
    )
    puts "✓ Reasoning response: #{response.choices[0].message.content}"
    puts "  Tokens: #{response.usage.total_tokens}"
    puts "  Reasoning tokens: #{response.usage.completion_tokens_details&.reasoning_tokens}" if response.usage.respond_to?(:completion_tokens_details)
  end

  # Example 5: Multiple parameters
  puts "\n5. Advanced Parameters"
  puts "-" * 50
  tracer.in_span("example-advanced-params") do
    response = client.chat.completions.create(
      model: "gpt-4o-mini",
      messages: [
        {role: "system", content: "You are a helpful assistant. Be concise."},
        {role: "user", content: "What is Ruby?"}
      ],
      temperature: 0.7,
      top_p: 0.9,
      frequency_penalty: 0.5,
      presence_penalty: 0.5,
      max_tokens: 50,
      n: 1,
      seed: 12345
    )
    puts "✓ Response: #{response.choices[0].message.content[0..80]}..."
    puts "  Model: #{response.model}"
    puts "  System fingerprint: #{response.system_fingerprint}"
    puts "  Tokens: #{response.usage.total_tokens}"
  end
end # End of parent trace

puts "\n" + "=" * 50
puts "✓ All examples completed!"
puts "✓ View this trace at:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust!"
