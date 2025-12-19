#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "anthropic"
require "ruby_llm"
require "opentelemetry/sdk"

# Example: Auto-instrumentation via Braintrust.init
#
# This example demonstrates the auto_instrument feature introduced in Braintrust.init.
# Instead of manually calling Braintrust.instrument! for each LLM library, a single
# Braintrust.init call automatically detects and instruments all supported libraries.
#
# Supported libraries (when installed):
#   - openai (OpenAI's official Ruby gem)
#   - ruby-openai (alexrudall's ruby-openai gem) *
#   - anthropic (Anthropic's official Ruby gem)
#   - ruby_llm (RubyLLM unified interface)
#
# * Note: openai and ruby-openai share the same require path ("openai"), so only one
#   can be loaded at a time. This demo uses the official openai gem.
#
# Usage:
#   OPENAI_API_KEY=your-key ANTHROPIC_API_KEY=your-key \
#     bundle exec appraisal auto-instrument ruby examples/contrib/auto_instrument/init.rb

# Check for required API keys
missing_keys = []
missing_keys << "OPENAI_API_KEY" unless ENV["OPENAI_API_KEY"]
missing_keys << "ANTHROPIC_API_KEY" unless ENV["ANTHROPIC_API_KEY"]

unless missing_keys.empty?
  puts "Error: Missing required environment variables: #{missing_keys.join(", ")}"
  puts ""
  puts "Get your API keys from:"
  puts "  OpenAI: https://platform.openai.com/api-keys"
  puts "  Anthropic: https://console.anthropic.com/"
  exit 1
end

puts "Auto-Instrumentation Demo"
puts "=" * 50
puts ""
puts "Calling Braintrust.init..."
puts "This automatically detects and instruments all supported LLM libraries."
puts ""

# Configure RubyLLM before init (it needs API keys configured)
RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
end

# Single init call - auto_instrument is enabled by default!
# This detects openai, anthropic, and ruby_llm are loaded and instruments them.
Braintrust.init

# Brief pause to allow async Braintrust login to complete
# (Not necessary in production, just for this short lived example)
sleep 0.5

puts "Libraries will be instrumented as API calls are made."
puts ""

# Create clients for each library
openai_client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])
anthropic_client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])

# Create a tracer and root span to capture all operations
tracer = OpenTelemetry.tracer_provider.tracer("auto-instrument-demo")
root_span = nil

puts "Making API calls with each library..."
puts "-" * 50

tracer.in_span("examples/contrib/auto_instrument/init.rb") do |span|
  root_span = span

  # 1. OpenAI (official gem)
  puts ""
  puts "[1/3] OpenAI (official gem)..."
  openai_response = openai_client.chat.completions.create(
    model: "gpt-4o-mini",
    max_tokens: 50,
    messages: [
      {role: "user", content: "Say 'Hello from OpenAI!' in exactly 5 words."}
    ]
  )
  puts "      Response: #{openai_response.choices[0].message.content}"

  # 2. Anthropic
  puts ""
  puts "[2/3] Anthropic..."
  anthropic_response = anthropic_client.messages.create(
    model: "claude-3-haiku-20240307",
    max_tokens: 50,
    messages: [
      {role: "user", content: "Say 'Hello from Anthropic!' in exactly 5 words."}
    ]
  )
  puts "      Response: #{anthropic_response.content[0].text}"

  # 3. RubyLLM (using OpenAI provider)
  puts ""
  puts "[3/3] RubyLLM (via OpenAI)..."
  chat = RubyLLM.chat(model: "gpt-4o-mini")
  ruby_llm_response = chat.ask("Say 'Hello from RubyLLM!' in exactly 5 words.")
  puts "      Response: #{ruby_llm_response.content}"
end

puts ""
puts "-" * 50
puts ""
puts "All API calls complete!"
puts ""
puts "View trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"
puts ""

# Shutdown to flush spans
# (Not necessary in production, just for this short lived example)
OpenTelemetry.tracer_provider.shutdown

puts "Trace sent to Braintrust!"
