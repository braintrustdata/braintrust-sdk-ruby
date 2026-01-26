#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"
require "json"

# Internal example: Comprehensive OpenAI features with Braintrust tracing
#
# This example showcases ALL OpenAI features with proper tracing:
# 1. Vision (image understanding) with array content
# 2. Tool/function calling (single-turn)
# 3. Streaming chat completions with automatic chunk aggregation (stream_raw)
# 3a. Streaming with .text() convenience method
# 3b. Streaming with .get_final_completion() convenience method
# 3c. Streaming with .get_output_text() convenience method
# 4. Multi-turn tool calling with tool_call_id
# 5. Mixed content (text + images)
# 6. Reasoning models with advanced token metrics
# 7. Temperature variations
# 8. Advanced parameters
# 9. Responses API (non-streaming)
# 10. Responses API (streaming)
# 11. Moderations API
#
# This example validates that the Ruby SDK captures the same data as TypeScript/Go SDKs.
#
# Usage:
#   OPENAI_API_KEY=key bundle exec ruby examples/internal/contrib/openai/golden.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

Braintrust.init(
  default_project: "ruby-sdk-internal-examples",
  blocking_login: true
)

# Get a tracer for this example
tracer = OpenTelemetry.tracer_provider.tracer("openai-comprehensive-example")

# Create OpenAI client and instrument it
client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])
Braintrust.instrument!(:openai)

puts "OpenAI Comprehensive Features Example"
puts "=" * 50

# Wrap all examples under a single parent trace
root_span = nil
tracer.in_span("examples/internal/contrib/openai/golden.rb") do |span|
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
  rescue OpenAI::Errors::BadRequestError => e
    puts "⊘ Skipped - Image URL error (#{e.message.split("\n").first[0..80]}...)"
  rescue => e
    puts "⊘ Error: #{e.class}"
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

  # Example 3: Streaming Chat Completions (stream_raw method)
  puts "\n3. Streaming Chat Completions (stream_raw)"
  puts "-" * 50
  tracer.in_span("example-streaming-raw") do
    print "Streaming response: "
    stream = client.chat.completions.stream_raw(
      model: "gpt-4o-mini",
      messages: [
        {role: "user", content: "Count from 1 to 5"}
      ],
      max_tokens: 50,
      stream_options: {
        include_usage: true  # Request usage stats in stream
      }
    )

    # Consume and display the stream
    total_tokens = 0
    stream.each do |chunk|
      delta_content = chunk.choices[0]&.delta&.content
      print delta_content if delta_content

      # Capture usage from final chunk
      total_tokens = chunk.usage&.total_tokens if chunk.usage
    end
    puts ""
    puts "✓ Streaming complete, tokens: #{total_tokens}"
    puts "  (Note: Braintrust automatically aggregates all chunks for the trace)"
  end

  # Example 3a: Streaming with .stream() and .text() convenience method
  puts "\n3a. Streaming with .stream() and .text()"
  puts "-" * 50
  tracer.in_span("example-streaming-text") do
    print "Streaming text: "
    stream = client.chat.completions.stream(
      model: "gpt-4o-mini",
      messages: [
        {role: "user", content: "Say hello"}
      ],
      max_tokens: 20,
      stream_options: {
        include_usage: true
      }
    )

    # Use .text() convenience method to iterate over text deltas only
    stream.text.each do |delta|
      print delta
    end
    puts ""
    puts "✓ Streaming complete using .text() method"
    puts "  (Note: Span is automatically finished and metrics captured)"
  end

  # Example 3b: Streaming with .get_final_completion()
  puts "\n3b. Streaming with .get_final_completion()"
  puts "-" * 50
  tracer.in_span("example-streaming-final-completion") do
    stream = client.chat.completions.stream(
      model: "gpt-4o-mini",
      messages: [
        {role: "user", content: "Say hello"}
      ],
      max_tokens: 20,
      stream_options: {
        include_usage: true
      }
    )

    # Use .get_final_completion() to block and get the complete response
    completion = stream.get_final_completion
    puts "✓ Final completion: #{completion.choices[0].message.content}"
    puts "  Tokens: #{completion.usage&.total_tokens || "N/A"}"
    puts "  (Note: Span finished automatically after stream consumed)"
  end

  # Example 3c: Streaming with .get_output_text()
  puts "\n3c. Streaming with .get_output_text()"
  puts "-" * 50
  tracer.in_span("example-streaming-output-text") do
    stream = client.chat.completions.stream(
      model: "gpt-4o-mini",
      messages: [
        {role: "user", content: "Say hello"}
      ],
      max_tokens: 20,
      stream_options: {
        include_usage: true
      }
    )

    # Use .get_output_text() to block and get just the text
    output_text = stream.get_output_text
    puts "✓ Output text: #{output_text}"
    puts "  (Note: Span finished automatically after stream consumed)"
  end

  # Example 4: Multi-turn Tool Calling (with tool_call_id)
  puts "\n4. Multi-turn Tool Calling"
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

  # Example 5: Mixed Content (text + image in same message)
  puts "\n5. Mixed Content (Text + Image)"
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
  rescue OpenAI::Errors::BadRequestError
    puts "⊘ Skipped - Image URL error (same as Example 1)"
  rescue => e
    puts "⊘ Error: #{e.class}"
  end

  # Example 6: Reasoning Model (o1-mini) with Advanced Token Metrics
  puts "\n6. Reasoning Model (o1-mini)"
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
  rescue OpenAI::Errors::NotFoundError
    puts "⊘ Skipped - o1-mini model not available (404)"
  rescue => e
    puts "⊘ Error: #{e.class}"
  end

  # Example 7: Temperature & Parameter Variations
  puts "\n7. Temperature & Parameter Variations"
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

  # Example 8: Advanced Parameters Showcase
  puts "\n8. Advanced Parameters (metadata capture)"
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

  # Example 9: Responses API (Non-streaming)
  if client.respond_to?(:responses)
    puts "\n9. Responses API (Non-streaming)"
    puts "-" * 50
    tracer.in_span("example-responses-api") do
      response = client.responses.create(
        model: "gpt-4o-mini",
        instructions: "You are a helpful assistant that provides concise answers.",
        input: "What are three benefits of Ruby programming language?"
      )
      puts "✓ Response API output: #{response.output.first.content.first[:text][0..100]}..."
      puts "  Tokens: #{response.usage.total_tokens}"
      puts "  Response automatically traced by Braintrust"
    end

    # Example 10: Responses API (Streaming)
    puts "\n10. Responses API (Streaming)"
    puts "-" * 50
    tracer.in_span("example-responses-streaming") do
      print "Streaming response: "
      stream = client.responses.stream(
        model: "gpt-4o-mini",
        input: "Count from 1 to 5"
      )

      stream.each do |event|
        if event.type == :"response.output_text.delta"
          print event.delta
        end
      end
      puts ""
      puts "✓ Streaming complete"
      puts "  (Note: Braintrust automatically aggregates all events for the trace)"
    end
  else
    puts "\n9-10. Responses API examples skipped (not available in this OpenAI gem version)"
  end

  # Example 11: Moderations API
  if client.respond_to?(:moderations)
    puts "\n11. Moderations API"
    puts "-" * 50
    tracer.in_span("example-moderations") do
      response = client.moderations.create(
        input: "I love sunny days and spending time with friends.",
        model: "omni-moderation-latest"
      )
      result = response.results.first
      puts "✓ Moderation result:"
      puts "  Flagged: #{result.flagged}"
      puts "  Model: #{response.model}"

      # Show flagged categories if any
      flagged_categories = result.categories.to_h.select { |_, v| v }.keys
      if flagged_categories.any?
        puts "  Flagged categories: #{flagged_categories.join(", ")}"
      else
        puts "  No categories flagged (safe content)"
      end
    end
  else
    puts "\n11. Moderations API example skipped (not available in this OpenAI gem version)"
  end
end # End of parent trace

puts "\n" + "=" * 50
puts "✓ All examples completed!"
puts ""
puts "This golden example validates that the Ruby SDK properly captures:"
puts "  ✓ Vision messages with array content (text + image_url)"
puts "  ✓ Tool calling (single and multi-turn with tool_call_id)"
puts "  ✓ Streaming chat completions with chunk aggregation"
puts "  ✓ Streaming convenience methods (.text(), .get_final_completion(), .get_output_text())"
puts "  ✓ Mixed content messages (multiple text/image blocks)"
puts "  ✓ Advanced token metrics (cached, reasoning, audio tokens)"
puts "  ✓ All request parameters (temperature, top_p, seed, user, etc.)"
puts "  ✓ Full message structures (role, content, tool_calls, etc.)"
puts "  ✓ Responses API (non-streaming and streaming)"
puts "  ✓ Moderations API"
puts ""
puts "View this trace at:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust - check the UI to verify all fields!"
