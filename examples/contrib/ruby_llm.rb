#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "ruby_llm"
require "opentelemetry/sdk"

# Example: Basic RubyLLM chat with Braintrust tracing
#
# Usage:
#   OPENAI_API_KEY=your-key bundle exec appraisal ruby_llm ruby examples/contrib/ruby_llm.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

# Initialize Braintrust (with blocking login)
#
# NOTE: blocking_login is only necessary for this short-lived example.
#       In most production apps, you can omit this.
Braintrust.init(blocking_login: true)

RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
end

# Get a tracer and wrap the API call in a span
tracer = OpenTelemetry.tracer_provider.tracer("ruby-llm-example")

root_span = nil
tracer.in_span("examples/contrib/ruby_llm.rb") do |span|
  root_span = span

  # Make a chat request (automatically traced!)
  chat = RubyLLM.chat(model: "gpt-4o-mini")
  chat.ask("What is the capital of France?")
end

# Print permalink to view this trace in Braintrust
puts "\nView this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
#
# NOTE: shutdown is only necessary for this short-lived example.
#       In most production apps, you can omit this.
OpenTelemetry.tracer_provider.shutdown
