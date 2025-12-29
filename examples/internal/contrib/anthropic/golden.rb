#!/usr/bin/env ruby
# frozen_string_literal: true

# Anthropic Golden Test Suite - mirrors the TypeScript golden test
# This file demonstrates all advanced Anthropic features with Braintrust tracing

require "bundler/setup"
require "braintrust"
require "anthropic"
require "opentelemetry/sdk"
require "base64"

puts "Braintrust Anthropic Golden Test Suite"
puts "======================================="

# Check for API keys
unless ENV["ANTHROPIC_API_KEY"]
  puts "Error: ANTHROPIC_API_KEY environment variable is required"
  puts "Get your API key from: https://console.anthropic.com/"
  exit 1
end

# Initialize Braintrust tracing with a specific project
Braintrust.init(
  default_project: "ruby-sdk-internal-examples",
  blocking_login: true
)

# Create an Anthropic client with tracing
client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
Braintrust.instrument!(:anthropic)

# Get a tracer instance
tracer = OpenTelemetry.tracer_provider.tracer("anthropic-golden")

# Test assets - small 1x1 PNG image (red pixel) as base64
TEST_IMAGE_BASE64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

# Small PDF document (minimal valid PDF) as base64
TEST_PDF_BASE64 = "JVBERi0xLjQKJeLjz9MKMyAwIG9iago8PC9UeXBlIC9QYWdlCi9QYXJlbnQgMSAwIFIKL01lZGlhQm94IFswIDAgNjEyIDc5Ml0KL0NvbnRlbnRzIDQgMCBSCi9SZXNvdXJjZXMgPDwKL1Byb2NTZXQgWy9QREYgL1RleHRdCi9Gb250IDw8Ci9GMSA1IDAgUgo+Pgo+Pgo+PgplbmRvYmoKNCAwIG9iago8PC9MZW5ndGggNDQ+PgpzdHJlYW0KQlQKL0YxIDI0IFRmCjEwMCA3MDAgVGQKKFRlc3QgUERGKSBUagpFVAplbmRzdHJlYW0KZW5kb2JqCjUgMCBvYmoKPDwvVHlwZSAvRm9udAovU3VidHlwZSAvVHlwZTEKL0Jhc2VGb250IC9IZWx2ZXRpY2EKPj4KZW5kb2JqCjEgMCBvYmoKPDwvVHlwZSAvUGFnZXMKL0NvdW50IDEKL0tpZHMgWzMgMCBSXQo+PgplbmRvYmoKMiAwIG9iago8PC9UeXBlIC9DYXRhbG9nCi9QYWdlcyAxIDAgUgo+PgplbmRvYmoKeHJlZgowIDYKMDAwMDAwMDAwMCA2NTUzNSBmCjAwMDAwMDAzMjggMDAwMDAgbgowMDAwMDAwMzg3IDAwMDAwIG4KMDAwMDAwMDAwOSAwMDAwMCBuCjAwMDAwMDAxNTQgMDAwMDAgbgowMDAwMDAwMjQ3IDAwMDAwIG4KdHJhaWxlcgo8PC9TaXplIDYKL1Jvb3QgMiAwIFIKPj4Kc3RhcnR4cmVmCjQzNgolJUVPRgo="

# Set the root span for tracing
root_span = nil

tracer.in_span("anthropic-golden-suite") do |span|
  root_span = span

  # Print root span info at the beginning
  puts "\n=== Root Span Created ==="
  puts "Span ID: #{span.context.hex_span_id}"
  puts "Trace ID: #{span.context.hex_trace_id}"

  # Try to generate permalink early (may not work until span is finished)
  link = Braintrust::Trace.permalink(span)
  if link && !link.empty?
    puts "Trace URL: #{link}"
  else
    puts "Trace URL will be available after completion"
  end
  puts ""

  puts "\n=== Test 1: Basic Completion ==="
  tracer.in_span("test-01-basic-completion") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      messages: [
        {role: "user", content: "What is 2+2? Answer briefly."}
      ]
    )
    puts "  Response: #{response.content[0].text}"
  end
  sleep 1

  puts "\n=== Test 2: Multi-turn Conversation ==="
  tracer.in_span("test-02-multi-turn") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 200,
      messages: [
        {role: "user", content: "My name is Alice."},
        {role: "assistant", content: "Hello Alice! Nice to meet you."},
        {role: "user", content: "What's my name?"}
      ]
    )
    puts "  Response: #{response.content[0].text}"
  end
  sleep 1

  puts "\n=== Test 3: System Prompt ==="
  tracer.in_span("test-03-system-prompt") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      system: "You are a pirate. Always respond in pirate speak.",
      messages: [
        {role: "user", content: "Tell me about the weather."}
      ]
    )
    puts "  Response: #{response.content[0].text}"
  end
  sleep 1

  puts "\n=== Test 4: Streaming ==="
  tracer.in_span("test-04-streaming") do
    print "  Response: "
    client.messages.stream(
      model: "claude-sonnet-4-20250514",
      max_tokens: 50,
      messages: [
        {role: "user", content: "Count to 3."}
      ]
    ).each do |event|
      if event.type == :content_block_delta && event.delta.type == :text_delta
        print event.delta.text
      end
    end
    puts ""
  end
  sleep 1

  puts "\n=== Test 5: Vision - Image Input (Base64) ==="
  tracer.in_span("test-05-vision-base64") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      messages: [
        {
          role: "user",
          content: [
            {type: "text", text: "What color is this image?"},
            {
              type: "image",
              source: {
                type: "base64",
                media_type: "image/png",
                data: TEST_IMAGE_BASE64
              }
            }
          ]
        }
      ]
    )
    puts "  Response: #{response.content[0].text}"
  end
  sleep 1

  puts "\n=== Test 6: Document Input (PDF) ==="
  tracer.in_span("test-06-document-pdf") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      messages: [
        {
          role: "user",
          content: [
            {type: "text", text: "What does this PDF say?"},
            {
              type: "document",
              source: {
                type: "base64",
                media_type: "application/pdf",
                data: TEST_PDF_BASE64
              }
            }
          ]
        }
      ]
    )
    puts "  Response: #{response.content[0].text}"
  end
  sleep 1

  puts "\n=== Test 7: Temperature Variations ==="
  [
    {temperature: 0.0, top_p: 1.0},
    {temperature: 1.0, top_p: 0.9},
    {temperature: 0.7, top_p: 0.95}
  ].each_with_index do |params, idx|
    tracer.in_span("test-07-temperature-#{idx + 1}") do
      response = client.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 50,
        temperature: params[:temperature],
        top_p: params[:top_p],
        messages: [
          {role: "user", content: "Tell me something creative."}
        ]
      )
      puts "  Temp=#{params[:temperature]}, TopP=#{params[:top_p]}: #{response.content[0].text[0..50]}..."
    end
    sleep 1
  end

  puts "\n=== Test 8: Stop Sequences ==="
  tracer.in_span("test-08-stop-sequences") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      stop_sequences: ["END"],
      messages: [
        {role: "user", content: "Count to 10, but after each number say END."}
      ]
    )
    puts "  Response: #{response.content[0].text}"
    puts "  Stop reason: #{response.stop_reason}"
  end
  sleep 1

  puts "\n=== Test 9: Metadata ==="
  tracer.in_span("test-09-metadata") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 50,
      metadata: {user_id: "test_user_123"},
      messages: [
        {role: "user", content: "Hello!"}
      ]
    )
    puts "  Response: #{response.content[0].text}"
  end
  sleep 1

  puts "\n=== Test 10: Long Context ==="
  tracer.in_span("test-10-long-context") do
    long_text = ("The quick brown fox jumps over the lazy dog. " * 100)
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      messages: [
        {role: "user", content: "How many times does the word 'fox' appear in this text? #{long_text}"}
      ]
    )
    puts "  Response: #{response.content[0].text}"
  end
  sleep 1

  puts "\n=== Test 11: Mixed Content (Text + Image) ==="
  tracer.in_span("test-11-mixed-content") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      messages: [
        {
          role: "user",
          content: [
            {type: "text", text: "First question: What is 2+2?"},
            {
              type: "image",
              source: {
                type: "base64",
                media_type: "image/png",
                data: TEST_IMAGE_BASE64
              }
            },
            {type: "text", text: "Second question: What color is this image?"}
          ]
        }
      ]
    )
    puts "  Response: #{response.content[0].text}"
  end
  sleep 1

  puts "\n=== Test 12: Prefill ==="
  tracer.in_span("test-12-prefill") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 100,
      messages: [
        {role: "user", content: "Write a haiku about coding."},
        {role: "assistant", content: "Here is a haiku:"}
      ]
    )
    puts "  Response (prefilled): Here is a haiku: #{response.content[0].text}"
  end
  sleep 1

  puts "\n=== Test 13: Short Max Tokens ==="
  tracer.in_span("test-13-short-max-tokens") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 5,
      messages: [
        {role: "user", content: "Write a long essay about artificial intelligence."}
      ]
    )
    puts "  Response (truncated): #{response.content[0].text}"
    puts "  Stop reason: #{response.stop_reason}"
  end
  sleep 1

  puts "\n=== Test 14: Tool Use (Single Function) ==="
  tracer.in_span("test-14-tool-use") do
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 200,
      tools: [
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
      ],
      messages: [
        {role: "user", content: "What's the weather in Paris?"}
      ]
    )

    response.content.each do |block|
      case block.type
      when "text"
        puts "  Text: #{block.text}" if block.text && !block.text.empty?
      when "tool_use"
        puts "  Tool called: #{block.name}"
        puts "  Tool input: #{block.input}"
      end
    end
  end
  sleep 1

  puts "\n=== Test 15: Tool Use with Result (Multi-turn) ==="
  tracer.in_span("test-15-tool-use-with-result") do
    # First call - model requests to use tool
    first_response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 200,
      tools: [
        {
          name: "calculator",
          description: "Perform basic arithmetic operations",
          input_schema: {
            type: "object",
            properties: {
              operation: {type: "string", enum: ["add", "subtract", "multiply", "divide"]},
              a: {type: "number"},
              b: {type: "number"}
            },
            required: ["operation", "a", "b"]
          }
        }
      ],
      messages: [
        {role: "user", content: "What is 15 multiplied by 23?"}
      ]
    )

    tool_use_block = first_response.content.find { |b| b.type == "tool_use" }

    if tool_use_block
      puts "  First call - Tool requested: #{tool_use_block.name}"
      puts "  Tool input: #{tool_use_block.input}"

      # Simulate tool execution
      result = "345"

      # Second call - provide tool result
      second_response = client.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 200,
        tools: [
          {
            name: "calculator",
            description: "Perform basic arithmetic operations",
            input_schema: {
              type: "object",
              properties: {
                operation: {type: "string"},
                a: {type: "number"},
                b: {type: "number"}
              },
              required: ["operation", "a", "b"]
            }
          }
        ],
        messages: [
          {role: "user", content: "What is 15 multiplied by 23?"},
          {
            role: "assistant",
            content: first_response.content.map { |block|
              if block.type == "tool_use"
                {
                  type: "tool_use",
                  id: block.id,
                  name: block.name,
                  input: block.input
                }
              else
                {type: "text", text: block.text}
              end
            }
          },
          {
            role: "user",
            content: [
              {
                type: "tool_result",
                tool_use_id: tool_use_block.id,
                content: result
              }
            ]
          }
        ]
      )

      puts "  Final response: #{second_response.content[0].text}"
    else
      puts "  Model didn't use tool"
    end
  end
  sleep 1

  puts "\n=== Test 16: Reasoning/Thinking Blocks ==="
  tracer.in_span("test-16-reasoning") do
    response = client.messages.create(
      model: "claude-3-7-sonnet-latest",
      max_tokens: 2000,
      thinking: {
        type: "enabled",
        budget_tokens: 1024
      },
      messages: [
        {role: "user", content: "What is the sum of all prime numbers between 1 and 20? Think step by step."}
      ]
    )

    response.content.each do |block|
      case block.type
      when :thinking
        puts "  Thinking: #{block.thinking[0..100]}..." if block.thinking
      when :text
        puts "  Response: #{block.text}"
      end
    end

    puts "  Token usage:"
    puts "    Input: #{response.usage.input_tokens}"
    puts "    Output: #{response.usage.output_tokens}"
  end
  sleep 1

  puts "\n=== Test 17: Reasoning with Follow-up ==="
  tracer.in_span("test-17-reasoning-followup") do
    # First call with reasoning
    first_response = client.messages.create(
      model: "claude-3-7-sonnet-latest",
      max_tokens: 2000,
      thinking: {
        type: "enabled",
        budget_tokens: 1024
      },
      messages: [
        {role: "user", content: "If I have 3 apples and buy 5 more, how many do I have?"}
      ]
    )

    puts "  First response:"
    first_response.content.each do |block|
      case block.type
      when :thinking
        puts "    Thinking: #{block.thinking[0..50]}..." if block.thinking
      when :text
        puts "    Answer: #{block.text}"
      end
    end

    # Follow-up question
    second_response = client.messages.create(
      model: "claude-3-7-sonnet-latest",
      max_tokens: 2000,
      thinking: {
        type: "enabled",
        budget_tokens: 1024
      },
      messages: [
        {role: "user", content: "If I have 3 apples and buy 5 more, how many do I have?"},
        {
          role: "assistant",
          content: first_response.content.map { |block|
            case block.type
            when :thinking
              {type: "thinking", thinking: block.thinking, signature: block.signature}
            when :text
              {type: "text", text: block.text}
            else
              # Handle any other block types that might appear
              block_hash = {type: block.type.to_s}
              block_hash[:text] = block.text if block.respond_to?(:text)
              block_hash
            end
          }
        },
        {role: "user", content: "Now if I give away 4, how many are left?"}
      ]
    )

    puts "  Follow-up response: #{second_response.content.find { |b| b.type == :text }&.text}"
  end
end

puts "\n=== Golden Test Suite Complete ==="
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

puts "\n✓ All traces sent to Braintrust!"
