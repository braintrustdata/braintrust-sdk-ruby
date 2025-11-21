#!/usr/bin/env ruby
# frozen_string_literal: true

# Gemini kitchen sink - tests all the Gemini features with minimal code

require "bundler/setup"
require "braintrust"
require "gemini-ai"
require "opentelemetry/sdk"

puts "Braintrust Gemini Tracing Examples"
puts "==================================="

# Check for API keys
unless ENV["GOOGLE_API_KEY"]
  puts "Error: GOOGLE_API_KEY environment variable is required"
  puts "Get your API key from: https://makersuite.google.com/app/apikey"
  exit 1
end

# Model to use for all examples
MODEL = "gemini-pro"

# Initialize Braintrust tracing with a specific project
Braintrust.init(
  default_project: "ruby-sdk-internal-examples",
  blocking_login: true
)

# Create a Gemini client with tracing
client = Gemini.new(
  credentials: {
    service: "generative-language-api",
    api_key: ENV["GOOGLE_API_KEY"]
  },
  options: {model: MODEL}
)
Braintrust::Trace::Gemini.wrap(client)

# Get a tracer instance
tracer = OpenTelemetry.tracer_provider.tracer("gemini-examples")

# Set the root span for tracing
root_span = nil

tracer.in_span("gemini-examples") do |span|
  root_span = span

  puts "\nGemini Content Generation Examples"
  puts "===================================="
  puts "Demonstrating: basic generation, streaming, parameters, multimodal"

  # ======================
  # Example 1: Basic Content Generation
  # ======================
  puts "\n=== Example 1: Basic Generation ==="

  tracer.in_span("basic-generation") do
    result = client.generate_content({
      contents: {
        role: "user",
        parts: {text: "What is the capital of France? Answer in one sentence."}
      }
    })

    response_text = result[0]["candidates"][0]["content"]["parts"][0]["text"]
    puts "  #{response_text}"
  end

  # ======================
  # Example 2: Streaming Content Generation
  # ======================
  puts "\n=== Example 2: Streaming Generation ==="

  tracer.in_span("streaming-generation") do
    # Create client with streaming enabled
    streaming_client = Gemini.new(
      credentials: {
        service: "generative-language-api",
        api_key: ENV["GOOGLE_API_KEY"]
      },
      options: {model: MODEL, server_sent_events: true}
    )
    Braintrust::Trace::Gemini.wrap(streaming_client)

    result = streaming_client.stream_generate_content({
      contents: {
        role: "user",
        parts: {text: "Count from 1 to 5."}
      }
    })

    # Aggregate the streaming response
    if result.is_a?(Array) && result.any?
      full_text = result.map do |chunk|
        chunk["candidates"]&.first&.dig("content", "parts")&.first&.dig("text")
      end.compact.join

      puts "  #{full_text}"
    end
  end

  # ======================
  # Example 3: Multi-turn Conversation
  # ======================
  puts "\n=== Example 3: Multi-turn Conversation ==="

  tracer.in_span("conversation") do
    result = client.generate_content({
      contents: [
        {
          role: "user",
          parts: {text: "Hello, my name is Alice."}
        },
        {
          role: "model",
          parts: {text: "Hello Alice! Nice to meet you."}
        },
        {
          role: "user",
          parts: {text: "What is my name?"}
        }
      ]
    })

    response_text = result[0]["candidates"][0]["content"]["parts"][0]["text"]
    puts "  #{response_text}"
  end

  # ======================
  # Example 4: Generation with Parameters
  # ======================
  puts "\n=== Example 4: Generation with Parameters ==="

  tracer.in_span("with-parameters") do
    result = client.generate_content({
      contents: {
        role: "user",
        parts: {text: "Write a creative short poem about Ruby programming."}
      },
      temperature: 0.9,
      top_p: 0.95,
      top_k: 40,
      max_output_tokens: 200,
      candidate_count: 1
    })

    response_text = result[0]["candidates"][0]["content"]["parts"][0]["text"]
    puts "  #{response_text}"
  end

  # ======================
  # Example 5: Multimodal with Base64 Image
  # ======================
  puts "\n=== Example 5: Multimodal (Image + Text) ==="

  # Use gemini-pro-vision for multimodal
  vision_client = Gemini.new(
    credentials: {
      service: "generative-language-api",
      api_key: ENV["GOOGLE_API_KEY"]
    },
    options: {model: "gemini-pro-vision"}
  )
  Braintrust::Trace::Gemini.wrap(vision_client)

  tracer.in_span("multimodal") do
    # Small 1x1 red pixel as base64 (for testing)
    red_pixel_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

    result = vision_client.generate_content({
      contents: {
        role: "user",
        parts: [
          {text: "Describe this image."},
          {
            inline_data: {
              mime_type: "image/png",
              data: red_pixel_base64
            }
          }
        ]
      }
    })

    response_text = result[0]["candidates"][0]["content"]["parts"][0]["text"]
    puts "  #{response_text}"
  end

  # ======================
  # Example 6: Error Handling
  # ======================
  puts "\n=== Example 6: Error Handling ==="

  tracer.in_span("error-handling") do
    # Try with an invalid model to test error handling
    error_client = Gemini.new(
      credentials: {
        service: "generative-language-api",
        api_key: ENV["GOOGLE_API_KEY"]
      },
      options: {model: "invalid-model"}
    )
    Braintrust::Trace::Gemini.wrap(error_client)

    error_client.generate_content({
      contents: {
        role: "user",
        parts: {text: "test"}
      }
    })
  rescue => e
    puts "  ✓ Error caught and traced: #{e.class.name}"
    puts "    Message: #{e.message[0..100]}..."
  end
end

# Print permalink to view this trace in Braintrust
puts "\n✓ View all traces in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ All traces sent to Braintrust!"
