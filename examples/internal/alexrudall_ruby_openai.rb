#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"
require "json"

# Internal example: Comprehensive ruby-openai (alexrudall) features with Braintrust tracing
#
# This golden example showcases ALL ruby-openai chat completion features with proper tracing:
# 1. Vision (image understanding) with array content [SKIPPED - needs investigation]
# 2. Tool/function calling (single-turn)
# 3. Streaming chat completions with automatic chunk aggregation
# 4. Multi-turn tool calling with tool_call_id
# 5. Mixed content (text + images) [SKIPPED - needs investigation]
# 6. Reasoning models with advanced token metrics
# 7. Temperature variations
# 8. Advanced parameters
#
# This example validates that the ruby-openai integration captures the SAME DATA
# as the openai gem integration for identical inputs.
#
# Usage:
#   OPENAI_API_KEY=key bundle exec appraisal ruby-openai ruby examples/internal/alexrudall_ruby_openai.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

Braintrust.init(blocking_login: true)

# Get a tracer for this example
tracer = OpenTelemetry.tracer_provider.tracer("alexrudall-ruby-openai-comprehensive-example")

# Create OpenAI client (ruby-openai style) and wrap it
client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
Braintrust::Trace::AlexRudall::RubyOpenAI.wrap(client)

puts "ruby-openai (alexrudall) Comprehensive Features Example"
puts "=" * 60

# Wrap all examples under a single parent trace
root_span = nil
tracer.in_span("examples/internal/alexrudall_ruby_openai.rb") do |span|
  root_span = span

  # Example 1: Vision - Image Understanding [SKIPPED]
  puts "\n1. Vision (Image Understanding)"
  puts "-" * 60
  tracer.in_span("example-vision") do
    puts "⊘ Skipped - Array content not yet supported for ruby-openai"
    puts "  (Simple text messages work, but vision array content needs investigation)"
  end

  # Example 2: Tool/Function Calling
  # EXACT SAME INPUT as openai.rb to verify same trace data
  puts "\n2. Tool/Function Calling"
  puts "-" * 60
  tracer.in_span("example-tools") do
    response = client.chat(
      parameters: {
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
      }
    )

    message = response.dig("choices", 0, "message")
    if message["tool_calls"]&.any?
      tool_call = message["tool_calls"][0]
      puts "✓ Tool called: #{tool_call.dig("function", "name")}"
      puts "  Arguments: #{tool_call.dig("function", "arguments")}"
    else
      puts "✓ Response: #{message["content"]}"
    end
    puts "  Tokens: #{response.dig("usage", "total_tokens")}"
  end

  # Example 3: Streaming Chat Completions
  # EXACT SAME INPUT as openai.rb (except using proc-based API)
  puts "\n3. Streaming Chat Completions"
  puts "-" * 60
  tracer.in_span("example-streaming") do
    print "Streaming response: "

    # ruby-openai uses proc-based streaming
    full_content = ""
    total_tokens = 0
    client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          {role: "user", content: "Count from 1 to 5"}
        ],
        max_tokens: 50,
        stream: proc do |chunk, _bytesize|
          delta_content = chunk.dig("choices", 0, "delta", "content")
          if delta_content
            print delta_content
            full_content += delta_content
          end
          # Capture usage from final chunk if available
          total_tokens = chunk.dig("usage", "total_tokens") if chunk["usage"]
        end
      }
    )

    puts ""
    puts "✓ Streaming complete#{", tokens: #{total_tokens}" if total_tokens > 0}"
    puts "  (Note: Braintrust automatically aggregates all chunks for the trace)"
  end

  # Example 4: Multi-turn Tool Calling (with tool_call_id)
  # EXACT SAME INPUT as openai.rb to verify same trace data
  puts "\n4. Multi-turn Tool Calling"
  puts "-" * 60
  tracer.in_span("example-multi-turn-tools") do
    # First request - model decides to call a tool
    first_response = client.chat(
      parameters: {
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
      }
    )

    tool_call = first_response.dig("choices", 0, "message", "tool_calls", 0)
    if tool_call
      puts "✓ First turn - Tool called: #{tool_call.dig("function", "name")}"
      puts "  Arguments: #{tool_call.dig("function", "arguments")}"

      # Simulate tool execution (same calculation as openai.rb)
      result = 127 * 49

      # Second request - provide tool result using tool_call_id
      second_response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {role: "user", content: "What is 127 multiplied by 49?"},
            first_response.dig("choices", 0, "message"),  # Assistant message with tool_calls
            {
              role: "tool",
              tool_call_id: tool_call["id"],
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
        }
      )

      puts "✓ Second turn - Response: #{second_response.dig("choices", 0, "message", "content")}"
      first_tokens = first_response.dig("usage", "total_tokens") || 0
      second_tokens = second_response.dig("usage", "total_tokens") || 0
      puts "  Tokens (total across both turns): #{first_tokens + second_tokens}"
    else
      puts "⊘ Model didn't call tool"
    end
  end

  # Example 5: Mixed Content (text + image in same message) [SKIPPED]
  puts "\n5. Mixed Content (Text + Image)"
  puts "-" * 60
  tracer.in_span("example-mixed-content") do
    puts "⊘ Skipped - Array content not yet supported for ruby-openai"
    puts "  (Same issue as Example 1 - vision array content needs investigation)"
  end

  # Example 6: Standard Model with Math Reasoning
  # Using gpt-4o-mini since o1-mini requires specific tier access
  puts "\n6. Math Reasoning (gpt-4o-mini)"
  puts "-" * 60
  tracer.in_span("example-reasoning") do
    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          {
            role: "user",
            content: "If I have 3 apples and buy 2 more, then give away 1, how many do I have?"
          }
        ]
      }
    )
    content = response.dig("choices", 0, "message", "content")
    puts "✓ Reasoning response: #{content[0..80]}..."
    puts "  Tokens: #{response.dig("usage", "total_tokens")}"

    # Show advanced token metrics if available
    usage = response["usage"]
    if usage && usage["completion_tokens_details"]
      details = usage["completion_tokens_details"]
      puts "  Advanced metrics:"
      puts "    - Reasoning tokens: #{details["reasoning_tokens"]}" if details["reasoning_tokens"]
      puts "    - Audio tokens: #{details["audio_tokens"]}" if details["audio_tokens"]
    end

    if usage && usage["prompt_tokens_details"]
      details = usage["prompt_tokens_details"]
      puts "    - Cached tokens: #{details["cached_tokens"]}" if details["cached_tokens"]
    end
  rescue Faraday::ResourceNotFound
    puts "⊘ Skipped - o1-mini model not available (404)"
    puts "  (Model may require special API access or different model name)"
  rescue => e
    puts "⊘ Error: #{e.class} - #{e.message[0..100]}"
  end

  # Example 7: Temperature & Parameter Variations
  # EXACT SAME INPUT as openai.rb to verify same trace data
  puts "\n7. Temperature & Parameter Variations"
  puts "-" * 60
  tracer.in_span("example-temperature-variations") do
    [0.0, 0.7, 1.0].each do |temp|
      response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [
            {role: "user", content: "Name a color"}
          ],
          temperature: temp,
          max_tokens: 5
        }
      )
      puts "✓ temp=#{temp}: #{response.dig("choices", 0, "message", "content")}"
    end
  end

  # Example 8: Advanced Parameters Showcase
  # EXACT SAME INPUT as openai.rb to verify same trace data
  puts "\n8. Advanced Parameters (metadata capture)"
  puts "-" * 60
  tracer.in_span("example-advanced-params") do
    response = client.chat(
      parameters: {
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
      }
    )
    content = response.dig("choices", 0, "message", "content")
    puts "✓ Response: #{content[0..80]}..."
    puts "  Model: #{response["model"]}"
    puts "  System fingerprint: #{response["system_fingerprint"]}"
    puts "  Tokens: #{response.dig("usage", "total_tokens")}"
    puts "  All params captured in metadata for Braintrust trace"
  end

  # Examples 9-10: Responses API
  # ruby-openai doesn't have a dedicated Responses API equivalent
  puts "\n9-10. Responses API examples skipped (ruby-openai uses standard chat API)"
end # End of parent trace

puts "\n" + "=" * 60
puts "✓ All examples completed!"
puts ""
puts "This golden example validates that ruby-openai integration captures:"
puts "  ✓ Tool calling (single and multi-turn with tool_call_id) ✓"
puts "  ✓ Streaming chat completions with chunk aggregation ✓"
puts "  ✓ Advanced token metrics (cached, reasoning, audio tokens) ✓"
puts "  ✓ All request parameters (temperature, top_p, seed, user, etc.) ✓"
puts "  ✓ Full message structures (role, content, tool_calls, etc.) ✓"
puts "  ⊘ Vision messages with array content (skipped - needs investigation)"
puts "  ⊘ Mixed content messages (skipped - same issue as vision)"
puts ""
puts "VERIFICATION: Compare this trace with examples/internal/openai.rb"
puts "  → Both should capture IDENTICAL data for matching examples (2-4, 6-8)"
puts "  → Input/output JSON, metadata, metrics should match exactly"
puts ""
puts "View this trace at:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ Trace sent to Braintrust - check the UI to verify all fields match!"
