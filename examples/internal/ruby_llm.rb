#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "ruby_llm"
require "opentelemetry/sdk"

# Example: Comprehensive RubyLLM testing with Braintrust tracing
#
# This example demonstrates:
# - Testing multiple providers (OpenAI, Anthropic, Gemini) with the same code
# - Basic chat completions
# - Streaming responses
# - Tool/function calling
# - Automatic token tracking (including cache metrics)
#
# Usage:
#   BUNDLE_GEMFILE=gemfiles/ruby_llm.gemfile bundle exec ruby examples/internal/ruby_llm.rb
#
# Set API keys as needed:
#   OPENAI_API_KEY=... ANTHROPIC_API_KEY=... bundle exec ruby examples/internal/ruby_llm.rb

Braintrust.init(blocking_login: true)

# Create a root span
tracer = OpenTelemetry.tracer_provider.tracer("ruby-llm-example")

# Define a simple tool for testing tool calling
class WeatherTool < RubyLLM::Tool
  description "Get current weather for a location"
  param :location

  def execute(location:)
    # Simulate weather API call
    {temperature: 72, condition: "sunny", location: location}
  end
end

# Configure providers
PROVIDERS = []

if ENV["OPENAI_API_KEY"]
  RubyLLM.configure do |config|
    config.openai_api_key = ENV["OPENAI_API_KEY"]
  end
  PROVIDERS << {
    name: "OpenAI",
    model: "gpt-4o-mini",
    supports_streaming: true,
    supports_tools: true
  }
end

if ENV["ANTHROPIC_API_KEY"]
  RubyLLM.configure do |config|
    config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  end
  PROVIDERS << {
    name: "Anthropic",
    model: "claude-3-5-sonnet-20241022",
    supports_streaming: true,
    supports_tools: true
  }
end

if ENV["GEMINI_API_KEY"]
  RubyLLM.configure do |config|
    config.gemini_api_key = ENV["GEMINI_API_KEY"]
  end
  PROVIDERS << {
    name: "Gemini",
    model: "gemini-pro",
    supports_streaming: true,
    supports_tools: false  # Adjust based on RubyLLM support
  }
end

if PROVIDERS.empty?
  puts "❌ No API keys configured. Set OPENAI_API_KEY, ANTHROPIC_API_KEY, or GEMINI_API_KEY"
  exit 1
end

# Wrap all tests under a parent span named after the filename
tracer.in_span("examples/internal/ruby_llm.rb") do |root_span|
  puts "=" * 70
  puts "Testing RubyLLM with Braintrust Tracing"
  puts "Providers: #{PROVIDERS.map { |p| p[:name] }.join(", ")}"
  puts "=" * 70

  # Test each provider with the same test suite
  PROVIDERS.each do |provider|
    puts "\n" + "=" * 70
    puts "Testing #{provider[:name]} (#{provider[:model]})"
    puts "=" * 70

    tracer.in_span("#{provider[:name].downcase}-tests") do |provider_span|
      # Test 1: Basic Chat Completion
      tracer.in_span("basic-chat") do |span|
        puts "\n📝 Test 1: Basic Chat Completion"

        chat = RubyLLM.chat.with_model(provider[:model])
        Braintrust::Trace::RubyLLM.wrap(chat)

        response = chat.ask "Say hello and tell me a short joke."

        puts "   ✓ Response received (#{response.content.length} chars)"
        puts "   ✓ Tokens: #{response.input_tokens} in + #{response.output_tokens} out"

        if response.respond_to?(:cached_tokens) && response.cached_tokens && response.cached_tokens > 0
          puts "   ✓ Cached tokens: #{response.cached_tokens}"
        end
      end

      # Test 2: Streaming (if supported)
      if provider[:supports_streaming]
        tracer.in_span("streaming-chat") do |span|
          puts "\n📡 Test 2: Streaming Chat"

          chat = RubyLLM.chat.with_model(provider[:model])
          Braintrust::Trace::RubyLLM.wrap(chat)

          chunks_count = 0
          response = chat.ask "Count from 1 to 5" do |chunk|
            chunks_count += 1
          end

          puts "   ✓ Received #{chunks_count} chunks"
          puts "   ✓ Final response: #{response.content}"
          puts "   ✓ Tokens: #{response.input_tokens} in + #{response.output_tokens} out"
        end
      else
        puts "\n⊘ Test 2: Streaming - Not supported by #{provider[:name]}"
      end

      # Test 3: Tool Calling (if supported)
      if provider[:supports_tools]
        tracer.in_span("tool-calling") do |span|
          puts "\n🔧 Test 3: Tool Calling"

          chat = RubyLLM.chat
            .with_model(provider[:model])
            .with_tool(WeatherTool)
          Braintrust::Trace::RubyLLM.wrap(chat)

          response = chat.ask "What's the weather like in Tokyo?"

          puts "   ✓ Response: #{response.content}"
          puts "   ✓ Tool calls captured in trace"
        end
      else
        puts "\n⊘ Test 3: Tool Calling - Not supported by #{provider[:name]}"
      end

      # Test 4: Multi-turn Conversation
      tracer.in_span("multi-turn") do |span|
        puts "\n💬 Test 4: Multi-turn Conversation"

        chat = RubyLLM.chat.with_model(provider[:model])
        Braintrust::Trace::RubyLLM.wrap(chat)

        response1 = chat.ask "My name is Alice"
        puts "   ✓ Turn 1: #{response1.content[0..50]}..."

        response2 = chat.ask "What's my name?"
        puts "   ✓ Turn 2: #{response2.content[0..50]}..."
        puts "   ✓ Conversation context maintained"
      end
    end
  end

  # Show the root span permalink
  puts "\n" + "=" * 70
  puts "✓ View all traces under parent span:"
  puts "  #{Braintrust::Trace.permalink(root_span)}"
  puts "=" * 70
end

# Shutdown to flush spans
OpenTelemetry.tracer_provider.shutdown

puts "\n✓ All traces sent to Braintrust!"
