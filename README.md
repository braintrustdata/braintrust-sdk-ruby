# Braintrust Ruby SDK

[![Gem Version](https://img.shields.io/gem/v/braintrust.svg)](https://rubygems.org/gems/braintrust)
[![Documentation](https://img.shields.io/badge/docs-rubydoc.info-blue.svg)](https://rubydoc.info/gems/braintrust)
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

Braintrust.init

# Define task to evaluate
task = ->(input) { input.include?("a") ? "fruit" : "vegetable" }

# Run evaluation
Braintrust::Eval.run(
  project: "my-project",
  experiment: "food-classifier",
  cases: [
    {input: "apple", expected: "fruit"},
    {input: "carrot", expected: "vegetable"}
  ],
  task: task,
  scorers: [
    ->(input, expected, output) { output == expected ? 1.0 : 0.0 }
  ]
)
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

### Auto-Instrumentation

The simplest way to trace LLM calls is with auto-instrumentation, which automatically wraps supported libraries when you initialize Braintrust:

```ruby
require "braintrust"
require "openai"

# Enable auto-instrumentation for all supported libraries
Braintrust.init(autoinstrument: { enabled: true })

# All OpenAI clients created after init are automatically traced!
client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])

response = client.chat.completions.create(
  messages: [{role: "user", content: "Hello!"}],
  model: "gpt-4o-mini"
)

# Spans are automatically created and sent to Braintrust
```

You can control which libraries are instrumented:

```ruby
# Only instrument specific libraries (allowlist)
Braintrust.init(autoinstrument: {
  enabled: true,
  include: [:openai, :anthropic]
})

# Instrument all except specific libraries (denylist)
Braintrust.init(autoinstrument: {
  enabled: true,
  exclude: [:anthropic]
})
```

**Supported libraries:** `:openai`, `:anthropic`

**Important notes:**
- Auto-instrumentation is **off by default** - you must explicitly enable it
- Only clients created **after** `Braintrust.init` are auto-instrumented
- Auto-instrumentation only affects new client instances, not existing ones
- You can still use manual wrapping alongside auto-instrumentation

### OpenAI Tracing (Manual)

```ruby
require "braintrust"
require "openai"

Braintrust.init

client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])

Braintrust::Trace::OpenAI.wrap(client)

tracer = OpenTelemetry.tracer_provider.tracer("openai-app")
root_span = nil

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

puts "View trace at: #{Braintrust::Trace.permalink(root_span)}"

OpenTelemetry.tracer_provider.shutdown
```

### Anthropic Tracing (Manual)

```ruby
require "braintrust"
require "anthropic"

Braintrust.init

client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])

Braintrust::Trace::Anthropic.wrap(client)

tracer = OpenTelemetry.tracer_provider.tracer("anthropic-app")
root_span = nil

message = tracer.in_span("chat-message") do |span|
  root_span = span

  client.messages.create(
    model: "claude-3-5-sonnet-20241022",
    max_tokens: 100,
    system: "You are a helpful assistant.",
    messages: [
      {role: "user", content: "Say hello!"}
    ]
  )
end

puts "Response: #{message.content[0].text}"

puts "View trace at: #{Braintrust::Trace.permalink(root_span)}"

OpenTelemetry.tracer_provider.shutdown
```

## Features

- **Evaluations**: Run systematic evaluations of your AI systems with custom scoring functions
- **Tracing**: Automatic instrumentation for OpenAI and Anthropic API calls with OpenTelemetry
- **Datasets**: Manage and version your evaluation datasets
- **Experiments**: Track different versions and configurations of your AI systems
- **Observability**: Monitor your AI applications in production

## Examples

Check out the [`examples/`](./examples/) directory for complete working examples:

- [eval.rb](./examples/eval.rb) - Create and run evaluations with custom test cases and scoring functions
- [trace.rb](./examples/trace.rb) - Manual span creation and tracing
- [openai.rb](./examples/openai.rb) - Automatically trace OpenAI API calls
- [anthropic.rb](./examples/anthropic.rb) - Automatically trace Anthropic API calls
- [eval/dataset.rb](./examples/eval/dataset.rb) - Run evaluations using datasets stored in Braintrust
- [eval/remote_functions.rb](./examples/eval/remote_functions.rb) - Use remote scoring functions

## Documentation

- [Braintrust Documentation](https://www.braintrust.dev/docs)
- [API Documentation](https://rubydoc.info/gems/braintrust)

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup and contribution guidelines.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](./LICENSE) file for details.
