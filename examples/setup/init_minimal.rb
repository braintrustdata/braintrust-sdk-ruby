#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Minimal auto-instrumentation via Braintrust.init
#
# Single Braintrust.init call auto-detects and instruments all supported LLM libraries.
#
# Usage:
#   OPENAI_API_KEY=your-key ANTHROPIC_API_KEY=your-key \
#     bundle exec appraisal contrib ruby examples/setup/init_minimal.rb

require "bundler/setup"
require "braintrust"
require "openai"
require "anthropic"
require "ruby_llm"
require "opentelemetry/sdk"

RubyLLM.configure { |c| c.openai_api_key = ENV["OPENAI_API_KEY"] }

Braintrust.init

# Brief pause to allow async Braintrust login to complete
# (Not necessary in production, just for this short lived example)
sleep 0.5

openai_client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])
anthropic_client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
tracer = OpenTelemetry.tracer_provider.tracer("auto-instrument-demo")

tracer.in_span("examples/setup/init_minimal.rb") do
  openai_client.chat.completions.create(
    model: "gpt-4o-mini",
    messages: [{role: "user", content: "Hello from OpenAI"}]
  )

  anthropic_client.messages.create(
    model: "claude-3-haiku-20240307",
    max_tokens: 50,
    messages: [{role: "user", content: "Hello from Anthropic"}]
  )

  RubyLLM.chat(model: "gpt-4o-mini").ask("Hello from RubyLLM")
end

# Shutdown to flush spans
# (Not necessary in production, just for this short lived example)
OpenTelemetry.tracer_provider.shutdown
