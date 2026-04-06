#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "llm"
require "opentelemetry/sdk"

# Example: Basic llm.rb chat with Braintrust tracing
#
# Usage:
#   OPENAI_API_KEY=your-key bundle exec appraisal llm.rb ruby examples/contrib/llm_rb.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

# Initialize Braintrust (with blocking login)
#
# NOTE: blocking_login is only necessary for this short-lived example.
#       In most production apps, you can omit this.
Braintrust.init(blocking_login: true)

llm = LLM.openai(key: ENV["OPENAI_API_KEY"])
ctx = LLM::Context.new(llm)

# Instrument this context instance to produce Braintrust spans
Braintrust.instrument!(:llm_rb, target: ctx)

# Get a tracer and wrap the conversation in a root span
tracer = OpenTelemetry.tracer_provider.tracer("llm-rb-example")

root_span = nil
tracer.in_span("examples/contrib/llm_rb.rb") do |span|
  root_span = span

  # Each ctx.talk call is automatically traced as a child span
  ctx.talk("What is the capital of France?")
  ctx.talk("And what is the population of that city?")
end

# Print permalink to view this trace in Braintrust
puts "\nView this trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans to Braintrust
#
# NOTE: shutdown is only necessary for this short-lived example.
#       In most production apps, you can omit this.
OpenTelemetry.tracer_provider.shutdown
