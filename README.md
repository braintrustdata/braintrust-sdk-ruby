# Braintrust Ruby SDK

[![Gem Version](https://badge.fury.io/rb/braintrust.svg)](https://badge.fury.io/rb/braintrust)
![Beta](https://img.shields.io/badge/status-beta-yellow)

## Overview

This library provides tools for **evaluating** and **tracing** AI applications in [Braintrust](https://www.braintrust.dev). Use it to:

- **Evaluate** your AI models with custom test cases and scoring functions
- **Trace** LLM calls and monitor AI application performance with OpenTelemetry
- **Integrate** seamlessly with OpenAI and other LLM providers

This SDK is currently in BETA status and APIs may change.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'braintrust'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install braintrust
```

## Quick Start

### Set up your API key

```bash
export BRAINTRUST_API_KEY="your-api-key"
```

### Evals

```ruby
require "braintrust"

# Initialize Braintrust
Braintrust.init

# Simple food classifier (the code being evaluated)
def classify_food(input)
  fruit = %w[apple banana strawberry orange grape mango]
  vegetable = %w[carrot broccoli spinach potato tomato cucumber]

  input_lower = input.downcase
  return "fruit" if fruit.any? { |f| input_lower.include?(f) }
  return "vegetable" if vegetable.any? { |v| input_lower.include?(v) }
  "unknown"
end

# Run an evaluation
result = Braintrust::Eval.run(
  project: "my-project",
  experiment: "food-classifier-eval",

  # Test cases
  cases: [
    {input: "apple", expected: "fruit"},
    {input: "carrot", expected: "vegetable"},
    {input: "banana", expected: "fruit"},
    {input: "broccoli", expected: "vegetable"}
  ],

  # Task to evaluate
  task: ->(input) { classify_food(input) },

  # Scorers to judge output quality
  scorers: [
    Braintrust::Eval.scorer("exact_match") { |input, expected, output|
      (output == expected) ? 1.0 : 0.0
    }
  ],

  # Optional: Run 3 cases in parallel
  parallelism: 3
)

# View results
puts "View results at: #{result.permalink}"
```

### Tracing

```ruby
require "braintrust"
require "opentelemetry/sdk"

# Initialize Braintrust
Braintrust.init

# Get a tracer
tracer = OpenTelemetry.tracer_provider.tracer("my-app")

# Create spans to track operations
tracer.in_span("process-data") do |span|
  span.set_attribute("user.id", "123")
  span.set_attribute("operation.type", "data_processing")

  # Your code here
  puts "Processing data..."
  sleep 0.1

  # Nested spans are automatically linked
  tracer.in_span("nested-operation") do |nested_span|
    nested_span.set_attribute("step", "1")
    puts "Nested operation..."
  end
end

# Shutdown to flush spans
OpenTelemetry.tracer_provider.shutdown

puts "View trace in Braintrust!"
```

### OpenAI Tracing

```ruby
require "braintrust"
require "openai"

# Initialize Braintrust
Braintrust.init

# Create OpenAI client
client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])

# Wrap the client with Braintrust tracing
Braintrust::Trace::OpenAI.wrap(client)

# Create a root span to capture the operation
tracer = OpenTelemetry.tracer_provider.tracer("openai-app")
root_span = nil

# Make a chat completion request (automatically traced!)
response = tracer.in_span("chat-completion") do |span|
  root_span = span

  client.chat.completions.create(
    messages: [
      {role: "system", content: "You are a helpful assistant."},
      {role: "user", content: "Say hello!"}
    ],
    model: "gpt-4o-mini",
    max_tokens: 100
  )
end

puts "Response: #{response.choices[0].message.content}"

# View the trace
puts "View trace at: #{Braintrust::Trace.permalink(root_span)}"

# Shutdown to flush spans
OpenTelemetry.tracer_provider.shutdown
```

## Features

- **Evaluations**: Run systematic evaluations of your AI systems with custom scoring functions
- **Tracing**: Automatic instrumentation for OpenAI API calls with OpenTelemetry
- **Datasets**: Manage and version your evaluation datasets
- **Experiments**: Track different versions and configurations of your AI systems
- **Observability**: Monitor your AI applications in production

## Examples

Check out the [`examples/`](./examples/) directory for complete working examples:

- [eval.rb](./examples/eval.rb) - Create and run evaluations with custom test cases and scoring functions
- [trace.rb](./examples/trace.rb) - Manual span creation and tracing
- [openai.rb](./examples/openai.rb) - Automatically trace OpenAI API calls
- [eval/dataset.rb](./examples/eval/dataset.rb) - Run evaluations using datasets stored in Braintrust
- [eval/remote_functions.rb](./examples/eval/remote_functions.rb) - Use remote scoring functions

## Documentation

- [Braintrust Documentation](https://www.braintrust.dev/docs)
- [API Documentation](https://rubydoc.info/gems/braintrust)

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup and contribution guidelines.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](./LICENSE) file for details.
