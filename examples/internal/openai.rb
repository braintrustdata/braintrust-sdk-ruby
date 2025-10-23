#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"
require "json"

# Internal example: Comprehensive OpenAI features with Braintrust tracing
#
# This golden example showcases ALL OpenAI chat completion features with proper tracing:
# 1. Vision (image understanding) with array content
# 2. Tool/function calling (single-turn)
# 3. Multi-turn tool calling with tool_call_id
# 4. Mixed content (text + images)
# 5. Reasoning models with advanced token metrics
# 6. Temperature variations and other parameters
#
# This example validates that the Ruby SDK captures the same data as TypeScript/Go SDKs.
#
# Usage:
#   OPENAI_API_KEY=key bundle exec ruby examples/internal/openai.rb

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

  # Example 3: Multi-turn Tool Calling (with tool_call_id)
  puts "\n3. Multi-turn Tool Calling"
  puts "-" * 50
  tracer.in_span("example-multi-turn-tools") do
    # First request - model decides to call a tool
    first_response = client.chat.completions.create(
      model: "gpt-4o-mini",
      messages: [
        {role: "user", content: "What is 127 multiplied by 49?"}
      ],
      tools: [
        {
          type: "function",
          function: {
            name: "calculate",
            description: "Perform a mathematical calculation",
            parameters: {
              type: "object",
              properties: {
                operation: {type: "string", enum: ["add", "subtract", "multiply", "divide"]},
                a: {type: "number"},
                b: {type: "number"}
              },
              required: ["operation", "a", "b"]
            }
          }
        }
      ],
      max_tokens: 100
    )

    tool_call = first_response.choices[0].message.tool_calls&.first
    if tool_call
      puts "✓ First turn - Tool called: #{tool_call.function.name}"
      puts "  Arguments: #{tool_call.function.arguments}"

      # Simulate tool execution
      result = 127 * 49

      # Second request - provide tool result using tool_call_id
      second_response = client.chat.completions.create(
        model: "gpt-4o-mini",
        messages: [
          {role: "user", content: "What is 127 multiplied by 49?"},
          first_response.choices[0].message.to_h,  # Assistant message with tool_calls
          {
            role: "tool",
            tool_call_id: tool_call.id,
            content: result.to_s
          }
        ],
        tools: [
          {
            type: "function",
            function: {
              name: "calculate",
              description: "Perform a mathematical calculation",
              parameters: {
                type: "object",
                properties: {
                  operation: {type: "string", enum: ["add", "subtract", "multiply", "divide"]},
                  a: {type: "number"},
                  b: {type: "number"}
                },
                required: ["operation", "a", "b"]
              }
            }
          }
        ],
        max_tokens: 100
      )

      puts "✓ Second turn - Response: #{second_response.choices[0].message.content}"
      puts "  Tokens (total across both turns): #{first_response.usage.total_tokens + second_response.usage.total_tokens}"
    else
      puts "⊘ Model didn't call tool"
    end
  end

  # Example 4: Mixed Content (text + image in same message)
  puts "\n4. Mixed Content (Text + Image)"
  puts "-" * 50
  tracer.in_span("example-mixed-content") do
    response = client.chat.completions.create(
      model: "gpt-4o-mini",
      messages: [
        {
          role: "user",
          content: [
            {type: "text", text: "Look at this boardwalk:"},
            {
              type: "image_url",
              image_url: {
                url: "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/320px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"
              }
            },
            {type: "text", text: "Describe the scene in 2 sentences."}
          ]
        }
      ],
      max_tokens: 100
    )
    puts "✓ Mixed content response: #{response.choices[0].message.content[0..100]}..."
    puts "  Tokens: #{response.usage.total_tokens}"
  end

  # Example 5: Reasoning Model (o1-mini) with Advanced Token Metrics
  puts "\n5. Reasoning Model (o1-mini)"
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
    puts "✓ Reasoning response: #{response.choices[0].message.content[0..80]}..."
    puts "  Tokens: #{response.usage.total_tokens}"

    # Show advanced token metrics if available
    if response.usage.respond_to?(:completion_tokens_details) && response.usage.completion_tokens_details
      details = response.usage.completion_tokens_details
      puts "  Advanced metrics:"
      puts "    - Reasoning tokens: #{details.reasoning_tokens}" if details.respond_to?(:reasoning_tokens) && details.reasoning_tokens
      puts "    - Audio tokens: #{details.audio_tokens}" if details.respond_to?(:audio_tokens) && details.audio_tokens
    end

    if response.usage.respond_to?(:prompt_tokens_details) && response.usage.prompt_tokens_details
      details = response.usage.prompt_tokens_details
      puts "    - Cached tokens: #{details.cached_tokens}" if details.respond_to?(:cached_tokens) && details.cached_tokens
    end
  end

  # Example 6: Temperature & Parameter Variations
  puts "\n6. Temperature & Parameter Variations"
  puts "-" * 50
  tracer.in_span("example-temperature-variations") do
    [0.0, 0.7, 1.0].each do |temp|
      response = client.chat.completions.create(
        model: "gpt-4o-mini",
        messages: [
          {role: "user", content: "Name a color"}
        ],
        temperature: temp,
        max_tokens: 5
      )
      puts "✓ temp=#{temp}: #{response.choices[0].message.content}"
    end
  end

  # Example 7: Advanced Parameters Showcase
  puts "\n7. Advanced Parameters (metadata capture)"
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
      seed: 12345,
      user: "golden-example-user"
    )
    puts "✓ Response: #{response.choices[0].message.content[0..80]}..."
    puts "  Model: #{response.model}"
    puts "  System fingerprint: #{response.system_fingerprint}"
    puts "  Tokens: #{response.usage.total_tokens}"
    puts "  All params captured in metadata for Braintrust trace"
  end
end # End of parent trace

puts "\n" + "=" * 50
puts "✓ All examples completed!"
puts ""
puts "This golden example validates that the Ruby SDK properly captures:"
puts "  ✓ Vision messages with array content (text + image_url)"
puts "  ✓ Tool calling (single and multi-turn with tool_call_id)"
puts "  ✓ Mixed content messages (multiple text/image blocks)"
puts "  ✓ Advanced token metrics (cached, reasoning, audio tokens)"
puts "  ✓ All request parameters (temperature, top_p, seed, user, etc.)"
puts "  ✓ Full message structures (role, content, tool_calls, etc.)"
puts ""
puts "View this trace at:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust - check the UI to verify all fields!"
