#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "opentelemetry/sdk"
require "ruby_llm"
require "openai"

project1 = "Project-A"
project2 = "Project-B"
model1 = "gpt-4o-mini"
model2 = "claude-sonnet-4"

# check for API keys
unless ENV["OPENAI_API_KEY"] && ENV["ANTHROPIC_API_KEY"]
  puts "Error: Both OPENAI_API_KEY and ANTHROPIC_API_KEY environment variables are required"
  puts "Get your API key from: https://platform.openai.com/api-keys"
  puts "Get your Anthropic API key from: https://console.anthropic.com/"
  puts "Set with `export OPENAI_API_KEY=<your_key> and export ANTHROPIC_API_KEY=<your_key>`"
  exit 1
end

unless ENV["BRAINTRUST_API_KEY"]
  puts "Error: BRAINTRUST_API_KEY environment variable is required"
  puts "Get your API key from https://www.braintrust.dev/app/settings or ask your org administrator"
  exit 1
end

# Example: Log/Trace to Multiple Projects with Separate States
#
# This example demonstrates how to:
# 1. Create multiple Braintrust states for different projects
# 2. Set up separate tracer providers for each project
# 3. Log traces to different projects simultaneously
#
# Usage:
#   bundle exec ruby examples/trace/multiple_projects.rb

# Create first state for Project A (non-global)
state_a = Braintrust.init(
  default_project: project1,
  set_global: false,
  enable_tracing: false,  # We'll manually set up tracing
  blocking_login: true    # Ensure login completes before tracing setup
  # Not required if only tracing, login is async by default and can lead to a broken permalink if not synchronous
)
# Create second state for Project B (non-global)
state_b = Braintrust.init(
  default_project: project2,
  set_global: false,
  enable_tracing: false,
  blocking_login: true 
)

# Wrap all instances of RubyLLM client
Braintrust::Trace::Contrib::Github::Crmne::RubyLLM.wrap

RubyLLM.configure do |config|
    config.openai_api_key = ENV["OPENAI_API_KEY"]
    config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end

chat_openai = RubyLLM.chat(model: model1)
chat_anthropic = RubyLLM.chat(model: model2)

# Create first tracer provider
tracer_provider_a = OpenTelemetry::SDK::Trace::TracerProvider.new

# Setup using Trace.setup
# When you pass an explicit tracer_provider, it won't set it as global
Braintrust::Trace.setup(state_a, tracer_provider_a)

# Get tracer for Project A
tracer_a = tracer_provider_a.tracer("MultiTurn")

# Note: You can also use Trace.enable instead of Trace.setup:
# Braintrust::Trace.enable(tracer_provider_a, state: state_a)
# Braintrust::Trace.enable(tracer_provider_b, state: state_b)
# Both work the same when you provide explicit providers

# Now create spans in first project
puts "\nProject A: Multi-turn conversation"
puts "=" * 50
root_span_a = nil
tracer_a.in_span("chat_ask") do |span|
  root_span_a = span
  span.set_attribute("project", project1)

  # Nested spans for multi-turn convo
  tracer_a.in_span("turn1") do |nested_t1|
    # Using OTEL GenAI Semantic Conventions for properties
    # https://www.braintrust.dev/docs/integrations/sdk-integrations/opentelemetry#manual-tracing
    # Braintrust automatically maps `gen_ai.*` attributes to native Braintrust fields
    # tracer_b will use native fields
    nested_t1.set_attribute("gen_ai.operation.name", "chat")
    nested_t1.set_attribute("gen_ai.request.model", model1)
    input = "What is the best season to visit Japan?"
    puts "\nTurn 1 (#{model1}):"
    puts "Q: #{input}"
    output = chat_openai.ask(input)

    nested_t1.set_attribute("gen_ai.prompt", input)
    nested_t1.set_attribute("gen_ai.completion", output.content)
    puts "A: #{output.content[0..100]}..."
    puts "  Tokens: #{output.to_h[:input_tokens]} in, #{output.to_h[:output_tokens]} out"

    tracer_a.in_span("turn2") do |nested_t2|
      nested_t2.set_attribute("gen_ai.operation.name", "chat")
      nested_t2.set_attribute("gen_ai.request.model", model2)
      input = "Which airlines fly to Japan from SFO?"
      puts "\nTurn 2 (#{model2}):"
      puts "Q: #{input}"
      output = chat_anthropic.ask(input)

      nested_t2.set_attribute("gen_ai.prompt", input)
      nested_t2.set_attribute("gen_ai.completion", output.content)
      puts "A: #{output.content[0..100]}..."
      puts "  Tokens: #{output.to_h[:input_tokens]} in, #{output.to_h[:output_tokens]} out"
    end
  end
end

puts "\n✓ Multi-turn conversation completed"
puts "\n✓ View Project A trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span_a)}"

url = "https://upload.wikimedia.org/wikipedia/commons/thumb/6/65/Tokyo_Tower_during_daytime.jpg/330px-Tokyo_Tower_during_daytime.jpg"

# For second project, we'll use the Ruby OpenAI client
# You can log to multiple projects even if your clients use different client libs
client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])

# Create second tracer provider
tracer_provider_b = OpenTelemetry::SDK::Trace::TracerProvider.new
Braintrust::Trace.setup(state_b, tracer_provider_b)

# Get tracer for Project A
tracer_b = tracer_provider_b.tracer("ImageUpload")

# Wrapping OpenAI client with second trace provider
# We could simply call `wrap` without tracer_provider, but then it would be bound to our global state
Braintrust::Trace::OpenAI.wrap(client, tracer_provider: tracer_provider_b)

puts "\nProject B: Describe Image"
puts "=" * 50

# chat completion should automatically nest
root_span_b = nil
tracer_b.in_span("vision") do |span|
  root_span_b = span
  # Example 1: Vision - Image Understanding
  puts "\n Vision (Image Understanding)"
  puts "-" * 50

  input = "Tell me about this landmark."
  tracer_b.in_span("example-vision") do |nested|
    response = client.chat.completions.create(
      model: model1,
      messages: [
        {
          role: "user",
          content: [
            {type: "text", text: input},
            {
              type: "image_url",
              image_url: {
                url: url
              }
            }
          ]
        }
      ],
      max_tokens: 100
    )

    # Using Braintrust native span attributes
    # For comparisons with OTEL GenAI semantic convention properties,
    # see https://www.braintrust.dev/docs/integrations/sdk-integrations/opentelemetry#manual-tracing
    nested.set_attribute("braintrust.span_attributes.type", "llm")
    nested.set_attribute("metadata.model", model1)
    nested.set_attribute("braintrust.input", input)
    nested.set_attribute("braintrust.output", "#{response.choices[0].message.content}")

    puts "✓ Vision response: #{response.choices[0].message.content[0..100]}..."
    puts "  Tokens: #{response.usage.total_tokens}"
  rescue OpenAI::Errors::BadRequestError => e
    puts "⊘ Skipped - Image URL error (#{e.message.split("\n").first[0..80]}...)"
  rescue => e
    puts "⊘ Error: #{e.class}"
  end
end

puts "\n✓ Vision example completed"
puts "\n✓ View Project B trace in Braintrust:"
puts "  #{Braintrust::Trace.permalink(root_span_b)}"

# Shutdown both tracer providers to flush spans
tracer_provider_a.shutdown
tracer_provider_b.shutdown