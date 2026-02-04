#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Loading and executing prompts from Braintrust
#
# This example demonstrates how to:
# 1. Create a prompt (function) on the Braintrust server
# 2. Load it using Prompt.load
# 3. Build the prompt with Mustache variable substitution
# 4. Execute the prompt with OpenAI and get a response
#
# Benefits of loading prompts:
# - Centralized prompt management in Braintrust UI
# - Version control and A/B testing for prompts
# - No code deployment needed for prompt changes
# - Works with any LLM client (OpenAI, Anthropic, etc.)
# - Uses standard Mustache templating ({{variable}}, {{object.property}})

require "bundler/setup"
require "braintrust"
require "openai"

# Initialize Braintrust (auto-instruments OpenAI automatically)
Braintrust.init

# Create OpenAI client (auto-instrumented for tracing)
openai = OpenAI::Client.new

project_name = "ruby-sdk-examples"
prompt_slug = "greeting-prompt-#{Time.now.to_i}"

# First, create a prompt on the server
# In practice, you would create prompts via the Braintrust UI
puts "Creating prompt..."

api = Braintrust::API.new
api.functions.create(
  project_name: project_name,
  slug: prompt_slug,
  function_data: {type: "prompt"},
  prompt_data: {
    prompt: {
      type: "chat",
      messages: [
        {
          role: "system",
          content: "You are a friendly assistant. Respond in {{language}}. Keep responses brief (1-2 sentences)."
        },
        {
          role: "user",
          content: "Say hello to {{name}} and wish them a great {{time_of_day}}!"
        }
      ]
    },
    options: {
      model: "gpt-4o-mini",
      params: {temperature: 0.7, max_tokens: 100}
    }
  }
)
puts "Created prompt: #{prompt_slug}"

# Load the prompt using Prompt.load
puts "\nLoading prompt..."
prompt = Braintrust::Prompt.load(project: project_name, slug: prompt_slug)

puts "  ID: #{prompt.id}"
puts "  Slug: #{prompt.slug}"
puts "  Model: #{prompt.model}"

# Build the prompt with Mustache variable substitution
puts "\nBuilding prompt with variables..."
params = prompt.build(
  name: "Alice",
  language: "Spanish",
  time_of_day: "morning"
)

puts "  Model: #{params[:model]}"
puts "  Temperature: #{params[:temperature]}"
puts "  Messages:"
params[:messages].each do |msg|
  puts "    [#{msg[:role]}] #{msg[:content]}"
end

# Execute the prompt with OpenAI
puts "\nExecuting prompt with OpenAI..."
response = openai.chat.completions.create(**params)

puts "\nResponse:"
content = response.choices.first.message.content
puts "  #{content}"

# Clean up - delete the test prompt
puts "\nCleaning up..."
api.functions.delete(id: prompt.id)
puts "Done!"

# Flush traces
OpenTelemetry.tracer_provider.shutdown
