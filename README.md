# Braintrust Ruby SDK

[![Gem Version](https://img.shields.io/gem/v/braintrust.svg)](https://rubygems.org/gems/braintrust)
[![Documentation](https://img.shields.io/badge/docs-gemdocs.org-blue.svg)](https://gemdocs.org/gems/braintrust/)
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

### OpenAI Tracing

```ruby
require "braintrust"
require "openai"

Braintrust.init

client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])

# Instrument all clients
Braintrust.instrument!(:openai)
# OR instrument a single client
Braintrust.instrument!(:openai, target: client)

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

### Anthropic Tracing

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
    model: "claude-3-haiku-20240307",
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

### RubyLLM Tracing

```ruby
require "braintrust"
require "ruby_llm"

Braintrust.init

# Instrument all RubyLLM Chat instances
Braintrust.instrument!(:ruby_llm)

tracer = OpenTelemetry.tracer_provider.tracer("ruby-llm-app")
root_span = nil

response = tracer.in_span("chat") do |span|
  root_span = span

  chat = RubyLLM.chat(model: "gpt-4o-mini")
  chat.ask("Say hello!")
end

puts "Response: #{response.content}"

puts "View trace at: #{Braintrust::Trace.permalink(root_span)}"

OpenTelemetry.tracer_provider.shutdown
```

### Attachments

Attachments allow you to log binary data (images, PDFs, audio, etc.) as part of your traces. This is particularly useful for multimodal AI applications like vision models.

```ruby
require "braintrust"
require "braintrust/trace/attachment"

Braintrust.init

tracer = OpenTelemetry.tracer_provider.tracer("vision-app")

tracer.in_span("analyze-image") do |span|
  # Create attachment from file
  att = Braintrust::Trace::Attachment.from_file(
    Braintrust::Trace::Attachment::IMAGE_PNG,
    "./photo.png"
  )

  # Build message with attachment (OpenAI/Anthropic format)
  messages = [
    {
      role: "user",
      content: [
        {type: "text", text: "What's in this image?"},
        att.to_h  # Converts to {"type" => "base64_attachment", "content" => "data:..."}
      ]
    }
  ]

  # Log to trace
  span.set_attribute("braintrust.input_json", JSON.generate(messages))
end

OpenTelemetry.tracer_provider.shutdown
```

You can create attachments from bytes, files, or URLs:

```ruby
# From bytes
att = Braintrust::Trace::Attachment.from_bytes("image/jpeg", image_data)

# From file
att = Braintrust::Trace::Attachment.from_file("application/pdf", "./doc.pdf")

# From URL
att = Braintrust::Trace::Attachment.from_url("https://example.com/image.png")
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
- [alexrudall_openai.rb](./examples/alexrudall_openai.rb) - Automatically trace ruby-openai gem API calls
- [anthropic.rb](./examples/anthropic.rb) - Automatically trace Anthropic API calls
- [ruby_llm.rb](./examples/ruby_llm.rb) - Automatically trace RubyLLM API calls
- [trace/trace_attachments.rb](./examples/trace/trace_attachments.rb) - Log attachments (images, PDFs) in traces
- [eval/dataset.rb](./examples/eval/dataset.rb) - Run evaluations using datasets stored in Braintrust
- [eval/remote_functions.rb](./examples/eval/remote_functions.rb) - Use remote scoring functions

## Documentation

- [Braintrust Documentation](https://www.braintrust.dev/docs)
- [API Documentation](https://gemdocs.org/gems/braintrust/)

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup and contribution guidelines.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](./LICENSE) file for details.
