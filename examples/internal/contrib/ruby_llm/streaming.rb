#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "ruby_llm"
require "opentelemetry/sdk"

# Example: Streaming RubyLLM chat with Braintrust tracing
#
# Usage:
#   OPENAI_API_KEY=your-key bundle exec appraisal ruby_llm ruby examples/internal/contrib/ruby_llm/streaming.rb

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

puts "Streaming response..."
print "\nAssistant: "

tracer.in_span("examples/internal/contrib/ruby_llm/streaming.rb") do |span|
  root_span = span
  chat = RubyLLM.chat(model: "gpt-4o-mini")
  chat.ask("Write a haiku about programming") do |chunk|
    print chunk.content
  end
end

puts "\n\nView trace: #{Braintrust::Trace.permalink(root_span)}"

OpenTelemetry.tracer_provider.shutdown
