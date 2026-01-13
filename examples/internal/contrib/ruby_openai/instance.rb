#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"

# Example: Instance-level ruby-openai (alexrudall) instrumentation
#
# This shows how to instrument a specific client instance rather than
# all OpenAI clients globally.
#
# Usage:
#   OPENAI_API_KEY=your-key bundle exec appraisal ruby_openai ruby examples/internal/contrib/ruby_openai/instance.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

Braintrust.init(blocking_login: true)

# Create two client instances (ruby-openai uses access_token)
client_traced = ::OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
client_untraced = ::OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

# Only instrument one of them
Braintrust.instrument!(:ruby_openai, target: client_traced)

tracer = OpenTelemetry.tracer_provider.tracer("ruby-openai-example")
root_span = nil

tracer.in_span("examples/internal/contrib/ruby_openai/instance.rb") do |span|
  root_span = span

  puts "Calling traced client..."
  response1 = client_traced.chat(
    parameters: {
      messages: [{role: "user", content: "Say 'traced'"}],
      model: "gpt-4o-mini",
      max_tokens: 10
    }
  )
  puts "Traced response: #{response1.dig("choices", 0, "message", "content")}"

  puts "\nCalling untraced client..."
  response2 = client_untraced.chat(
    parameters: {
      messages: [{role: "user", content: "Say 'untraced'"}],
      model: "gpt-4o-mini",
      max_tokens: 10
    }
  )
  puts "Untraced response: #{response2.dig("choices", 0, "message", "content")}"
end

puts "\nView trace: #{Braintrust::Trace.permalink(root_span)}"
puts "(Only the first client call should have an openai.chat span)"

OpenTelemetry.tracer_provider.shutdown
