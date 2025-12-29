#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "ruby_llm"
require "opentelemetry/sdk"

# Example: Basic RubyLLM chat with Braintrust tracing
#
# Usage:
#   OPENAI_API_KEY=your-key bundle exec appraisal ruby_llm ruby examples/contrib/ruby_llm/basic.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

Braintrust.init(blocking_login: true)
Braintrust.instrument!(:ruby_llm)

RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
end

tracer = OpenTelemetry.tracer_provider.tracer("ruby_llm-example")
root_span = nil

puts "Sending chat request..."
response = tracer.in_span("examples/contrib/ruby_llm/basic.rb") do |span|
  root_span = span
  chat = RubyLLM.chat(model: "gpt-4o-mini")
  chat.ask("What is the capital of France?")
end

puts "\nAssistant: #{response.content}"
puts "\nToken usage:"
puts "  Input: #{response.to_h[:input_tokens]}"
puts "  Output: #{response.to_h[:output_tokens]}"
puts "\nView trace: #{Braintrust::Trace.permalink(root_span)}"

OpenTelemetry.tracer_provider.shutdown
