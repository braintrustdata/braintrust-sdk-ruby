#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "braintrust"
require "openai"
require "opentelemetry/sdk"
require "json"

# Kitchen Sink Example
#
# This example demonstrates many features of the Braintrust Ruby SDK:
# - OpenAI integration with function/tool calling
# - Complex task with error handling
# - Multiple scorer types (exact match, LLM-as-judge, custom)
# - Cases with tags, metadata, and expected outputs
# - Full OpenTelemetry tracing
#
# Usage:
#   OPENAI_API_KEY=key bundle exec ruby examples/internal/kitchen-sink.rb

unless ENV["OPENAI_API_KEY"]
  puts "Error: OPENAI_API_KEY environment variable is required"
  exit 1
end

Braintrust.init

# Create OpenAI client
openai_client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])

# Wrap the client with Braintrust tracing
Braintrust::Trace::OpenAI.wrap(openai_client)

puts "Kitchen Sink Eval Example"
puts "=" * 60

# Define tools/functions for OpenAI
def get_weather_tools
  [{
    type: "function",
    function: {
      name: "get_current_weather",
      description: "Get the current weather in a given location",
      parameters: {
        type: "object",
        properties: {
          location: {
            type: "string",
            description: "The city and state, e.g. San Francisco, CA"
          },
          unit: {
            type: "string",
            enum: ["celsius", "fahrenheit"],
            description: "The temperature unit to use"
          }
        },
        required: ["location"]
      }
    }
  }]
end

# Mock function to execute tool calls
def execute_tool_call(tool_call)
  if tool_call.function.name == "get_current_weather"
    args = JSON.parse(tool_call.function.arguments)
    location = args["location"]
    unit = args["unit"] || "fahrenheit"

    # Mock weather data
    temp = (unit == "celsius") ? 22 : 72
    {
      location: location,
      temperature: temp,
      unit: unit,
      conditions: "sunny"
    }.to_json
  end
end

# Complex task that uses OpenAI with tool calling
def weather_assistant_task(input, openai_client)
  messages = [
    {role: "system", content: "You are a helpful weather assistant. Use the get_current_weather function when asked about weather."},
    {role: "user", content: input}
  ]

  # First API call - may trigger tool calls
  response = openai_client.chat.completions.create(
    model: "gpt-4o-mini",
    messages: messages,
    tools: get_weather_tools,
    tool_choice: "auto",
    max_tokens: 150
  )

  choice = response.choices[0]

  # If there are tool calls, execute them and make another API call
  if choice.finish_reason == "tool_calls" && choice.message.tool_calls
    # Add assistant's message with tool calls
    messages << {
      role: "assistant",
      content: choice.message.content,
      tool_calls: choice.message.tool_calls.map { |tc|
        {
          id: tc.id,
          type: tc.type,
          function: {
            name: tc.function.name,
            arguments: tc.function.arguments
          }
        }
      }
    }

    # Execute each tool call and add results
    choice.message.tool_calls.each do |tool_call|
      result = execute_tool_call(tool_call)
      messages << {
        role: "tool",
        tool_call_id: tool_call.id,
        content: result
      }
    end

    # Second API call with tool results
    response = openai_client.chat.completions.create(
      model: "gpt-4o-mini",
      messages: messages,
      max_tokens: 150
    )
  end

  response.choices[0].message.content
end

# Scorers

# 1. Exact match scorer
exact_match_scorer = Braintrust::Eval.scorer("exact_match") do |input, expected, output|
  next 1.0 if expected.nil?
  next 0.0 if output.nil?
  (output == expected) ? 1.0 : 0.0
end

# 2. Contains keyword scorer
contains_keyword_scorer = Braintrust::Eval.scorer("contains_keyword") do |input, expected, output, metadata|
  keyword = metadata[:keyword]
  next 1.0 unless keyword
  next 0.0 if output.nil?

  output.downcase.include?(keyword.downcase) ? 1.0 : 0.0
end

# 3. LLM-as-judge scorer using OpenAI
class LLMJudgeScorer
  def initialize(openai_client, name, criterion)
    @openai_client = openai_client
    @name = name
    @criterion = criterion
  end

  attr_reader :name

  def call(input, expected, output, metadata = {})
    return 0.0 if output.nil?

    prompt = <<~PROMPT
      Evaluate the following response based on this criterion: #{@criterion}

      User Input: #{input}
      Assistant Response: #{output}
      #{"Expected Response: #{expected}" if expected}

      Score the response from 0.0 to 1.0 based on how well it meets the criterion.
      Respond with ONLY a number between 0.0 and 1.0, nothing else.
    PROMPT

    response = @openai_client.chat.completions.create(
      model: "gpt-4o-mini",
      messages: [{role: "user", content: prompt}],
      temperature: 0.0,
      max_tokens: 10
    )

    score_text = response.choices[0].message.content.strip
    score_text.to_f
  rescue => e
    puts "LLM Judge error: #{e.message}"
    0.5 # Default score on error
  end
end

# 4. Response length scorer
length_scorer = Braintrust::Eval.scorer("appropriate_length") do |input, expected, output|
  next 0.0 if output.nil?

  length = output.length
  # Penalize very short (< 20 chars) or very long (> 500 chars) responses
  if length < 20
    0.3
  elsif length > 500
    0.7
  else
    1.0
  end
end

# 5. Failing scorer (demonstrates error handling)
failing_scorer = Braintrust::Eval.scorer("error_demo") do |input, expected, output, metadata|
  # This scorer intentionally fails on a specific scenario
  if metadata[:scenario] == "ambiguous"
    raise "Intentional error: Cannot score ambiguous queries"
  end
  1.0 # Success for all other cases
end

# Create LLM judges
helpfulness_judge = LLMJudgeScorer.new(openai_client, "helpfulness", "does the response directly answer the question?")
accuracy_judge = LLMJudgeScorer.new(openai_client, "accuracy", "is the information provided accurate and relevant?")

# Test cases with various scenarios
test_cases = [
  # Successful case with tool calling
  {
    input: "What's the weather like in San Francisco?",
    expected: nil, # No exact expected output
    metadata: {keyword: "san francisco", scenario: "weather_query"},
    tags: ["weather", "tool_calling", "success"]
  },

  # Another weather query
  {
    input: "Tell me the temperature in New York City",
    expected: nil,
    metadata: {keyword: "new york", scenario: "weather_query"},
    tags: ["weather", "tool_calling", "success"]
  },

  # Non-weather query (no tool calling)
  {
    input: "What's the capital of France?",
    expected: "Paris",
    metadata: {keyword: "paris", scenario: "general_knowledge"},
    tags: ["general_knowledge", "no_tools", "success"]
  },

  # Query that might produce shorter response
  {
    input: "Say hello",
    expected: nil,
    metadata: {scenario: "short_response"},
    tags: ["greeting", "short"]
  },

  # Complex query combining weather and other info
  {
    input: "What's the weather in Seattle and what's the city known for?",
    expected: nil,
    metadata: {keyword: "seattle", scenario: "complex_query"},
    tags: ["weather", "general_knowledge", "complex"]
  },

  # Edge case - ambiguous location
  {
    input: "What's the weather in Paris?",
    expected: nil,
    metadata: {keyword: "paris", scenario: "ambiguous"},
    tags: ["weather", "ambiguous", "edge_case"]
  },

  # Multiple locations
  {
    input: "Compare the weather in Boston and Miami",
    expected: nil,
    metadata: {scenario: "multi_location"},
    tags: ["weather", "comparison", "complex"]
  },

  # Weather with specific unit preference
  {
    input: "What's the temperature in Tokyo in celsius?",
    expected: nil,
    metadata: {keyword: "celsius", scenario: "unit_preference"},
    tags: ["weather", "unit_conversion"]
  }
]

# Run the evaluation
puts "\nRunning comprehensive evaluation..."
puts "Cases: #{test_cases.length}"
puts "Scorers: 6 (exact_match, contains_keyword, appropriate_length, error_demo, helpfulness, accuracy)"
puts

result = Braintrust::Eval.run(
  project: "ruby-sdk-examples",
  experiment: "ruby-kitchen-sink-eval",

  cases: test_cases,

  # Task wraps the OpenAI call
  task: ->(input) { weather_assistant_task(input, openai_client) },

  # Multiple scorers of different types
  scorers: [
    exact_match_scorer,
    contains_keyword_scorer,
    length_scorer,
    failing_scorer,
    helpfulness_judge,
    accuracy_judge
  ],

  # Run 3 cases in parallel for speed
  parallelism: 3,

  # Tags for the experiment
  tags: ["kitchen-sink", "comprehensive", "openai", "tools"],

  # Metadata for the experiment
  metadata: {
    description: "Comprehensive eval demonstrating all SDK features",
    model: "gpt-4o-mini",
    sdk_version: Braintrust::VERSION,
    features: [
      "openai_integration",
      "tool_calling",
      "llm_as_judge",
      "custom_scorers",
      "error_handling",
      "tracing"
    ]
  }
)

# Print results
puts "\n" + "=" * 60
puts "Evaluation Complete!"
puts "=" * 60

puts "\nExperiment: #{result.experiment_name}"
puts "Project ID: #{result.project_id}"
puts "Duration: #{result.duration.round(2)}s"
puts "Status: #{result.success? ? "✓ Success" : "✗ Failed"}"

puts "\nView detailed results at:"
puts "  #{result.permalink}"

if result.failed?
  puts "\n⚠ Errors encountered (#{result.errors.length}):"
  result.errors.each_with_index do |error, i|
    puts "  #{i + 1}. #{error}"
  end
  puts "\nNote: Some errors are intentional to demonstrate error handling."
else
  puts "\n✓ All test cases completed successfully!"
end

# Shutdown to flush spans
OpenTelemetry.tracer_provider.shutdown
