#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Loading and using prompts from Braintrust
#
# This example demonstrates how to:
# 1. Create a prompt (function) on the Braintrust server
# 2. Load it using Prompt.load
# 3. Build the prompt with variable substitution
# 4. Use the built prompt with an LLM client
#
# Benefits of loading prompts:
# - Centralized prompt management in Braintrust UI
# - Version control and A/B testing for prompts
# - No code deployment needed for prompt changes
# - Works with any LLM client (OpenAI, Anthropic, etc.)

require "bundler/setup"
require "braintrust"

# Initialize Braintrust
Braintrust.init

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
          content: "You are a friendly assistant who speaks {{language}}."
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
puts "  Name: #{prompt.name}"
puts "  Model: #{prompt.model}"
puts "  Messages: #{prompt.messages.length}"

# Build the prompt with variable substitution
puts "\nBuilding prompt with variables..."
params = prompt.build(
  name: "Alice",
  language: "Spanish",
  time_of_day: "morning"
)

puts "  Model: #{params[:model]}"
puts "  Temperature: #{params[:temperature]}"
puts "  Max tokens: #{params[:max_tokens]}"
puts "  Messages:"
params[:messages].each do |msg|
  puts "    [#{msg[:role]}] #{msg[:content]}"
end

# The params hash is ready to pass to any LLM client:
#
# With OpenAI:
#   client.chat.completions.create(**params)
#
# With Anthropic:
#   client.messages.create(**params)

puts "\nPrompt is ready to use with any LLM client!"

# Clean up - delete the test prompt
api.functions.delete(id: prompt.id)
puts "Cleaned up test prompt."
