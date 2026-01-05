# Braintrust Ruby SDK

[![Gem Version](https://img.shields.io/gem/v/braintrust.svg)](https://rubygems.org/gems/braintrust)
[![Documentation](https://img.shields.io/badge/docs-gemdocs.org-blue.svg)](https://gemdocs.org/gems/braintrust/)
![Beta](https://img.shields.io/badge/status-beta-yellow)

This is the official Ruby SDK for [Braintrust](https://www.braintrust.dev), for tracing and evaluating your AI applications.

*NOTE: This SDK is currently in BETA status and APIs may change between minor versions.*

- [Quick Start](#quick-start)
- [Installation](#installation)
  - [CLI Command](#cli-command)
  - [Braintrust.init](#braintrustinit)
  - [Environment variables](#environment-variables)
- [Tracing](#tracing)
  - [Supported providers](#supported-providers)
  - [Manually applying instrumentation](#manually-applying-instrumentation)
  - [Creating custom spans](#creating-custom-spans)
  - [Attachments](#attachments)
  - [Viewing traces](#viewing-traces)
- [Evals](#evals)
  - [Datasets](#datasets)
  - [Remote scorers](#remote-scorers)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Quick Start

Add to your Gemfile:

```ruby
gem "braintrust", require: "braintrust/auto_instrument"
```

Set your API key and install:

```bash
export BRAINTRUST_API_KEY="your-api-key"
bundle install
```

Your LLM calls are now automatically traced. View them at [braintrust.dev](https://www.braintrust.dev).

## Installation

The SDK offers additional options for setup suitable for a variety of applications.

|                         | What it looks like                  | When to Use                                                                                |
| ----------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------ |
| [**CLI command**](#cli-command)         | `braintrust exec -- ruby app.rb`    | You prefer not to modify the application source code.                                      |
| [**Braintrust.init**](#braintrustinit)  | Call `Braintrust.init` in your code | You need to control when auto-instrumentation occurs, or require additional configuration. |

See [our examples](./examples/contrib/auto_instrument/README.md) for more detail.

### CLI Command

You can use this CLI command to instrument any Ruby application without modifying the source code.

First, make sure the gem is installed on the system:

```bash
gem install braintrust
```

Then wrap the start up command of any Ruby application to apply:

```bash
braintrust exec -- ruby app.rb
braintrust exec -- bundle exec rails server
braintrust exec --only openai -- ruby app.rb
```

You can use [environment variables](#environment-variables) to configure behavior.

---

*NOTE: Installing a package at the system-level does not guarantee compatibility with all Ruby applications on that system; conflicts with dependencies can arise.*

For stronger assurance of compatibility, we recommend either:

- Installing via the application's `Gemfile` and `bundle install` when possible.
- **OR** for OCI/Docker deployments, `gem install braintrust` when building images in your CI/CD pipeline (and verifying their safe function.)

---

### Braintrust.init

For more control over when auto-instrumentation is applied:

```ruby
require "braintrust"

Braintrust.init
```

**Options:**

| Option            | Default                                  | Description                                                                 |
| ----------------- | ---------------------------------------- | --------------------------------------------------------------------------- |
| `api_key`         | `ENV['BRAINTRUST_API_KEY']`              | API key                                                                     |
| `auto_instrument` | `true`                                   | `true`, `false`, or Hash with `:only`/`:except` keys to filter integrations |
| `blocking_login`  | `false`                                  | Block until login completes (async login when `false`)                      |
| `default_project` | `ENV['BRAINTRUST_DEFAULT_PROJECT']`      | Default project for spans                                                   |
| `enable_tracing`  | `true`                                   | Enable OpenTelemetry tracing                                                |
| `filter_ai_spans` | `ENV['BRAINTRUST_OTEL_FILTER_AI_SPANS']` | Only export AI-related spans                                                |
| `org_name`        | `ENV['BRAINTRUST_ORG_NAME']`             | Organization name                                                           |
| `set_global`      | `true`                                   | Set as global state. Set to `false` for isolated instances                  |

**Example with options:**

```ruby
Braintrust.init(
  default_project: "my-project",
  auto_instrument: { only: [:openai] }
)
```

### Environment variables

| Variable                          | Description                                                               |
| --------------------------------- | ------------------------------------------------------------------------- |
| `BRAINTRUST_API_KEY`              | Required. Your Braintrust API key                                         |
| `BRAINTRUST_API_URL`              | Braintrust API URL (default: `https://api.braintrust.dev`)                |
| `BRAINTRUST_APP_URL`              | Braintrust app URL (default: `https://www.braintrust.dev`)                |
| `BRAINTRUST_AUTO_INSTRUMENT`      | Set to `false` to disable auto-instrumentation                            |
| `BRAINTRUST_DEFAULT_PROJECT`      | Default project for spans                                                 |
| `BRAINTRUST_INSTRUMENT_EXCEPT`    | Comma-separated list of integrations to skip                              |
| `BRAINTRUST_INSTRUMENT_ONLY`      | Comma-separated list of integrations to enable (e.g., `openai,anthropic`) |
| `BRAINTRUST_ORG_NAME`             | Organization name                                                         |
| `BRAINTRUST_OTEL_FILTER_AI_SPANS` | Set to `true` to only export AI-related spans                             |

## Tracing

### Supported providers

The SDK automatically instruments these LLM libraries:

| Provider  | Gem           | Versions | Integration Name | Examples                                        |
| --------- | ------------- | -------- | ---------------- | ----------------------------------------------- |
| Anthropic | `anthropic`   | >= 0.3.0 | `:anthropic`     | [Link](./examples/contrib/anthropic/basic.rb)   |
| OpenAI    | `openai`      | >= 0.1.0 | `:openai`        | [Link](./examples/contrib/openai/basic.rb)      |
|           | `ruby-openai` | >= 7.0.0 | `:ruby_openai`   | [Link](./examples/contrib/ruby_openai/basic.rb) |
| Multiple  | `ruby_llm`    | >= 1.8.0 | `:ruby_llm`      | [Link](./examples/contrib/ruby_llm/basic.rb)    |

### Manually applying instrumentation

For fine-grained control, disable auto-instrumentation and instrument specific clients:

```ruby
require "braintrust"
require "openai"

Braintrust.init(auto_instrument: false) # Or BRAINTRUST_AUTO_INSTRUMENT=false

# Instrument all OpenAI clients
Braintrust.instrument!(:openai)

# OR instrument a single client
client = OpenAI::Client.new
Braintrust.instrument!(:openai, target: client)
```

### Creating custom spans

Wrap business logic in spans to see it in your traces:

```ruby
tracer = OpenTelemetry.tracer_provider.tracer("my-app")

tracer.in_span("process-request") do |span|
  span.set_attribute("user.id", user_id)

  # LLM calls inside here are automatically nested under this span
  response = client.chat.completions.create(...)
end
```

### Attachments

Log binary data (images, PDFs, audio) in your traces:

```ruby
require "braintrust/trace/attachment"

att = Braintrust::Trace::Attachment.from_file("image/png", "./photo.png")

# Use in messages (OpenAI/Anthropic format)
messages = [
  {
    role: "user",
    content: [
      {type: "text", text: "What's in this image?"},
      att.to_h
    ]
  }
]

# Log to span
span.set_attribute("braintrust.input_json", JSON.generate(messages))
```

Create attachments from various sources:

```ruby
Braintrust::Trace::Attachment.from_bytes("image/jpeg", image_data)
Braintrust::Trace::Attachment.from_file("application/pdf", "./doc.pdf")
Braintrust::Trace::Attachment.from_url("https://example.com/image.png")
```

See example: [trace_attachments.rb](./examples/trace/trace_attachments.rb)

### Viewing traces

Get a permalink to any span:

```ruby
tracer = OpenTelemetry.tracer_provider.tracer("my-app")

tracer.in_span("my-operation") do |span|
  # your code here
  puts "View trace at: #{Braintrust::Trace.permalink(span)}"
end
```

## Evals

Run evaluations against your AI systems:

```ruby
require "braintrust"

Braintrust.init

Braintrust::Eval.run(
  project: "my-project",
  experiment: "classifier-v1",
  cases: [
    {input: "apple", expected: "fruit"},
    {input: "carrot", expected: "vegetable"}
  ],
  task: ->(input) { classify(input) },
  scorers: [
    ->(input, expected, output) { output == expected ? 1.0 : 0.0 }
  ]
)
```

### Datasets

Load test cases from a Braintrust dataset:

```ruby
Braintrust::Eval.run(
  project: "my-project",
  dataset: "my-dataset",
  task: ->(input) { classify(input) },
  scorers: [...]
)
```

### Remote scorers

Use scoring functions defined in Braintrust:

```ruby
Braintrust::Eval.run(
  project: "my-project",
  cases: [...],
  task: ->(input) { ... },
  scorers: [
    Braintrust::Scorer.remote("my-project", "accuracy-scorer")
  ]
)
```

See examples: [eval.rb](./examples/eval.rb), [dataset.rb](./examples/eval/dataset.rb), [remote_functions.rb](./examples/eval/remote_functions.rb)

## Documentation

- [Braintrust Documentation](https://www.braintrust.dev/docs)
- [API Reference](https://gemdocs.org/gems/braintrust/)

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup and guidelines.

## License

Apache License 2.0 - see [LICENSE](./LICENSE).
