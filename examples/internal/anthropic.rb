#!/usr/bin/env ruby
# frozen_string_literal: true

# Anthropic kitchen sink - tests all the Anthropic features with minimal code

require "bundler/setup"
require "braintrust"
require "anthropic"
require "opentelemetry/sdk"

puts "Braintrust Anthropic Tracing Examples"
puts "======================================"

# Check for API keys
unless ENV["ANTHROPIC_API_KEY"]
  puts "Error: ANTHROPIC_API_KEY environment variable is required"
  puts "Get your API key from: https://console.anthropic.com/"
  exit 1
end

# Model to use for all examples
MODEL = "claude-sonnet-4-20250514"

# Initialize Braintrust tracing with a specific project
Braintrust.init(
  default_project: "ruby-sdk-internal-examples",
  blocking_login: true
)

# Create an Anthropic client with tracing
client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
Braintrust::Trace::Anthropic.wrap(client)

# Get a tracer instance
tracer = OpenTelemetry.tracer_provider.tracer("anthropic-examples")

# Set the experiment as parent for tracing
root_span = nil

tracer.in_span("anthropic-examples") do |span|
  root_span = span

  puts "\nAnthropic Messages Examples"
  puts "==========================="
  puts "Demonstrating: system prompts, tools, parameters, vision & non-streaming"

  # ======================
  # Example 1: Basic Messages
  # ======================
  puts "\n=== Example 1: Messages ==="

  tracer.in_span("messages") do
    message = client.messages.create(
      model: MODEL,
      max_tokens: 1024,
      system: "You are a helpful assistant.",
      messages: [
        {role: "user", content: "What is the capital of France?"}
      ],
      temperature: 0.7
    )

    puts "  #{message.content[0].text}"
  end

  # ======================
  # Example 2: Tools
  # ======================
  puts "\n=== Example 2: Tools ==="

  tracer.in_span("tools") do
    message = client.messages.create(
      model: MODEL,
      max_tokens: 1024,
      system: "You are a helpful weather assistant.",
      messages: [
        {role: "user", content: "What's the weather in San Francisco?"}
      ],
      temperature: 0.7,
      top_p: 0.9,
      top_k: 50,
      stop_sequences: ["END"],
      tools: [
        {
          name: "get_weather",
          description: "Get the current weather for a location",
          input_schema: {
            type: "object",
            properties: {
              location: {
                type: "string",
                description: "The city and state"
              }
            },
            required: ["location"]
          }
        }
      ]
    )

    message.content.each do |block|
      case block.type
      when "text"
        puts "  Text: #{block.text}"
      when "tool_use"
        puts "  Tool: #{block.name}"
        puts "  Input: #{block.input}"
      end
    end
  end

  # ======================
  # Example 3: Vision with URL
  # ======================
  puts "\n=== Example 3: Vision with URL ==="

  tracer.in_span("vision-url") do
    message = client.messages.create(
      model: MODEL,
      max_tokens: 300,
      messages: [
        {
          role: "user",
          content: [
            {type: "text", text: "Describe this image briefly."},
            {
              type: "image",
              source: {
                type: "url",
                url: "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/320px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"
              }
            }
          ]
        }
      ]
    )

    puts "  #{message.content[0].text}"
  end

  # ======================
  # Example 4: System Prompt with Multiple Parameters
  # ======================
  puts "\n=== Example 4: System Prompt with Parameters ==="

  tracer.in_span("system-prompt-params") do
    message = client.messages.create(
      model: MODEL,
      max_tokens: 200,
      system: "You are a concise technical writer.",
      messages: [
        {role: "user", content: "Explain what an API is in one sentence."}
      ],
      temperature: 0.5,
      top_p: 0.95
    )

    puts "  #{message.content[0].text}"
  end

  # ======================
  # Example 5: Tool Use with Multiple Tools
  # ======================
  puts "\n=== Example 5: Multiple Tools ==="

  tracer.in_span("multiple-tools") do
    message = client.messages.create(
      model: MODEL,
      max_tokens: 1024,
      messages: [
        {role: "user", content: "What time is it in Tokyo and what's the weather there?"}
      ],
      tools: [
        {
          name: "get_time",
          description: "Get the current time for a timezone",
          input_schema: {
            type: "object",
            properties: {
              timezone: {type: "string", description: "IANA timezone name"}
            },
            required: ["timezone"]
          }
        },
        {
          name: "get_weather",
          description: "Get the current weather for a location",
          input_schema: {
            type: "object",
            properties: {
              location: {type: "string", description: "City name"}
            },
            required: ["location"]
          }
        }
      ]
    )

    message.content.each do |block|
      case block.type
      when "text"
        puts "  Text: #{block.text}" if block.text && !block.text.empty?
      when "tool_use"
        puts "  Tool: #{block.name} - Input: #{block.input}"
      end
    end
  end

  # ======================
  # Example 6: Conversation with Tool Result
  # ======================
  puts "\n=== Example 6: Tool Result in Conversation ==="

  tracer.in_span("tool-result") do
    # First: Get tool call
    first_message = client.messages.create(
      model: MODEL,
      max_tokens: 1024,
      messages: [
        {role: "user", content: "What's the weather in Paris?"}
      ],
      tools: [
        {
          name: "get_weather",
          description: "Get the current weather",
          input_schema: {
            type: "object",
            properties: {
              location: {type: "string"}
            },
            required: ["location"]
          }
        }
      ]
    )

    tool_use_block = first_message.content.find { |b| b.type == "tool_use" }
    if tool_use_block
      # Second: Provide tool result
      second_message = client.messages.create(
        model: MODEL,
        max_tokens: 1024,
        messages: [
          {role: "user", content: "What's the weather in Paris?"},
          {
            role: "assistant",
            content: [
              {
                type: "tool_use",
                id: tool_use_block.id,
                name: tool_use_block.name,
                input: tool_use_block.input
              }
            ]
          },
          {
            role: "user",
            content: [
              {
                type: "tool_result",
                tool_use_id: tool_use_block.id,
                content: "Sunny, 22°C"
              }
            ]
          }
        ],
        tools: [
          {
            name: "get_weather",
            description: "Get the current weather",
            input_schema: {
              type: "object",
              properties: {
                location: {type: "string"}
              },
              required: ["location"]
            }
          }
        ]
      )

      puts "  #{second_message.content[0].text}"
    else
      puts "  (Model didn't use tool)"
    end
  end

  puts "\nAnthropic Streaming Examples"
  puts "============================"
  puts "Demonstrating: .each, .text.each, .accumulated_text"

  # ======================
  # Example 7: Basic Streaming with .each
  # ======================
  puts "\n=== Example 7: Streaming with .each ==="

  tracer.in_span("streaming-each") do
    print "  "
    client.messages.stream(
      model: MODEL,
      max_tokens: 100,
      messages: [
        {role: "user", content: "Count to 5"}
      ]
    ) do |event|
      if event.type == :content_block_delta && event.delta.type == :text_delta
        print event.delta.text
      end
    end
    puts # newline
  end

  # ======================
  # Example 8: Streaming with .text.each
  # ======================
  puts "\n=== Example 8: Streaming with .text.each ==="

  tracer.in_span("streaming-text-each") do
    stream = client.messages.stream(
      model: MODEL,
      max_tokens: 100,
      messages: [
        {role: "user", content: "Say hello"}
      ]
    )

    print "  "
    stream.text.each do |text|
      print text
    end
    puts # newline
  end

  # ======================
  # Example 9: Streaming with .accumulated_text
  # ======================
  puts "\n=== Example 9: Streaming with .accumulated_text ==="

  tracer.in_span("streaming-accumulated-text") do
    stream = client.messages.stream(
      model: MODEL,
      max_tokens: 100,
      messages: [
        {role: "user", content: "Tell me a very short joke"}
      ]
    )

    # Blocks until stream completes and returns full text
    text = stream.accumulated_text
    puts "  #{text}"
  end

  # ======================
  # Example 10: Streaming with .accumulated_message
  # ======================
  puts "\n=== Example 10: Streaming with .accumulated_message ==="

  tracer.in_span("streaming-accumulated-message") do
    stream = client.messages.stream(
      model: MODEL,
      max_tokens: 100,
      messages: [
        {role: "user", content: "What is 2+2?"}
      ]
    )

    # Blocks until stream completes and returns full Message object
    message = stream.accumulated_message
    puts "  #{message.content[0].text}"
    puts "  (Tokens: #{message.usage.input_tokens} in, #{message.usage.output_tokens} out)"
  end
end

puts "\n=== Tracing Complete ==="
puts "All examples completed successfully!"

# Print permalink to the top-level span
link = Braintrust::Trace.permalink(root_span)
if link && !link.empty?
  puts "View trace: #{link}"
else
  puts "Note: Permalink generation requires login"
end

# Shutdown to flush spans
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust!"
