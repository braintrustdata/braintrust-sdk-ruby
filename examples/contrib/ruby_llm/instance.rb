#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "ruby_llm"
require "opentelemetry/sdk"

# Example: Instance-level RubyLLM instrumentation
#
# This shows how to instrument a specific chat instance rather than
# all RubyLLM chats globally.
#
# Usage:
#   OPENAI_API_KEY=your-key bundle exec appraisal ruby_llm ruby examples/contrib/ruby_llm/instance_instrumentation.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

Braintrust.init(blocking_login: true)

RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
end

# Create two chat instances
chat_traced = RubyLLM.chat(model: "gpt-4o-mini")
chat_untraced = RubyLLM.chat(model: "gpt-4o-mini")

# Only instrument one of them
Braintrust.instrument!(:ruby_llm, target: chat_traced)

tracer = OpenTelemetry.tracer_provider.tracer("ruby_llm-example")
root_span = nil

tracer.in_span("examples/contrib/ruby_llm/instance_instrumentation.rb") do |span|
  root_span = span

  puts "Calling traced chat..."
  response1 = chat_traced.ask("Say 'traced'")
  puts "Traced response: #{response1.content}"

  puts "\nCalling untraced chat..."
  response2 = chat_untraced.ask("Say 'untraced'")
  puts "Untraced response: #{response2.content}"
end

puts "\nView trace: #{Braintrust::Trace.permalink(root_span)}"
puts "(Only the first chat call should have a ruby_llm.chat span)"

OpenTelemetry.tracer_provider.shutdown
