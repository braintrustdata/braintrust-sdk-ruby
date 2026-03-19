# Braintrust Ruby SDK

[![Gem Version](https://img.shields.io/gem/v/braintrust.svg)](https://rubygems.org/gems/braintrust)
[![Documentation](https://img.shields.io/badge/docs-gemdocs.org-blue.svg)](https://gemdocs.org/gems/braintrust/)
![Beta](https://img.shields.io/badge/status-beta-yellow)

This is the official Ruby SDK for [Braintrust](https://www.braintrust.dev), for tracing and evaluating your AI applications.

*NOTE: This SDK is currently in BETA status and APIs may change between minor versions.*

- [Quick Start](#quick-start)
- [Installation](#installation)
  - [Setup script](#setup-script)
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
  - [Scorers](#scorers)
  - [Dev Server](#dev-server)
- [Documentation](#documentation)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Quick Start

Add to your Gemfile:

```ruby
gem "braintrust", require: "braintrust/setup"
```

Set your API key and install:

```bash
export BRAINTRUST_API_KEY="your-api-key"
bundle install
```

Your LLM calls are now automatically traced. View them at [braintrust.dev](https://www.braintrust.dev).

## Installation

The SDK also offers additional setup options for a variety of applications.

|                                        | What it looks like                  | When to Use                                                                 |
| -------------------------------------- | ----------------------------------- | --------------------------------------------------------------------------- |
| [**Setup script**](#setup-script)      | `require 'braintrust/setup'`        | You'd like to automatically setup the SDK at load time.                     |
| [**CLI command**](#cli-command)        | `braintrust exec -- ruby app.rb`    | You prefer not to modify the application source code.                       |
| [**Braintrust.init**](#braintrustinit) | Call `Braintrust.init` in your code | You need to control when setup occurs, or require customized configuration. |

See [our examples](./examples/setup/README.md) for more detail.

### Setup script

For most applications, we recommend adding `require: "braintrust/setup"` to your `Gemfile` or an initializer file in your Ruby application to automatically setup the SDK. This will automatically apply instrumentation to all available LLM libraries.

You can use [environment variables](#environment-variables) to configure behavior.

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
| `BRAINTRUST_DEBUG`                | Set to `true` to enable debug logging                                     |
| `BRAINTRUST_DEFAULT_PROJECT`      | Default project for spans                                                 |
| `BRAINTRUST_FLUSH_ON_EXIT`        | Set to `false` to disable automatic span flushing on program exit         |
| `BRAINTRUST_INSTRUMENT_EXCEPT`    | Comma-separated list of integrations to skip                              |
| `BRAINTRUST_INSTRUMENT_ONLY`      | Comma-separated list of integrations to enable (e.g., `openai,anthropic`) |
| `BRAINTRUST_ORG_NAME`             | Organization name                                                         |
| `BRAINTRUST_OTEL_FILTER_AI_SPANS` | Set to `true` to only export AI-related spans                             |

## Tracing

### Supported providers

The SDK automatically instruments these LLM libraries:

| Provider  | Gem           | Versions | Integration Name | Examples                                  |
| --------- | ------------- | -------- | ---------------- | ----------------------------------------- |
| Anthropic | `anthropic`   | >= 0.3.0 | `:anthropic`     | [Link](./examples/contrib/anthropic.rb)   |
| OpenAI    | `openai`      | >= 0.1.0 | `:openai`        | [Link](./examples/contrib/openai.rb)      |
|           | `ruby-openai` | >= 7.0.0 | `:ruby_openai`   | [Link](./examples/contrib/ruby-openai.rb) |
| Multiple  | `ruby_llm`    | >= 1.8.0 | `:ruby_llm`      | [Link](./examples/contrib/ruby_llm.rb)    |

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
  task: ->(input:) { classify(input) },
  scorers: [
    ->(expected:, output:) { output == expected ? 1.0 : 0.0 }
  ]
)
```

See [eval.rb](./examples/eval.rb) for a full example.

### Datasets

Use test cases from a Braintrust dataset:

```ruby
Braintrust::Eval.run(
  project: "my-project",
  dataset: "my-dataset",
  task: ->(input:) { classify(input) },
  scorers: [...]
)
```

Or define test cases inline with metadata and tags:

```ruby
Braintrust::Eval.run(
  project: "my-project",
  experiment: "classifier-v1",
  cases: [
    {input: "apple", expected: "fruit", tags: ["produce"], metadata: {difficulty: "easy"}},
    {input: "salmon", expected: "protein", tags: ["seafood"], metadata: {difficulty: "medium"}}
  ],
  task: ->(input:) { classify(input) },
  scorers: [...]
)
```

See [dataset.rb](./examples/eval/dataset.rb) for a full example.

### Scorers

Use scoring functions defined in Braintrust:

```ruby
Braintrust::Eval.run(
  project: "my-project",
  cases: [...],
  task: ->(input:) { ... },
  scorers: ["accuracy-scorer"]
)
```

Or define scorers inline with `Scorer.new`:

```ruby
Braintrust::Eval.run(
  project: "my-project",
  cases: [...],
  task: ->(input:) { ... },
  scorers: [
    Braintrust::Scorer.new("exact_match") do |expected:, output:|
      output == expected ? 1.0 : 0.0
    end
  ]
)
```

See [remote_functions.rb](./examples/eval/remote_functions.rb) for a full example.

#### Scorer metadata

Scorers can return a Hash with `:score` and `:metadata` to attach structured context to the score. The metadata is logged on the scorer's span and visible in the Braintrust UI for debugging and filtering:

```ruby
Braintrust::Scorer.new("translation") do |expected:, output:|
  common_words = output.downcase.split & expected.downcase.split
  overlap = common_words.size.to_f / expected.split.size
  {
    score: overlap,
    metadata: {word_overlap: common_words.size, missing_words: expected.downcase.split - output.downcase.split}
  }
end
```

See [scorer_metadata.rb](./examples/eval/scorer_metadata.rb) for a full example.

#### Multiple scores from one scorer

When several scores can be computed together (e.g. in one LLM call), you can return an `Array` of score `Hash` instead of a single value. Each metric appears as a separate score column in the Braintrust UI:

```ruby
Braintrust::Scorer.new("summary_quality") do |output:, expected:|
  words = output.downcase.split
  key_terms = expected[:key_terms]
  covered = key_terms.count { |t| words.include?(t) }

  [
    {name: "coverage", score: covered.to_f / key_terms.size, metadata: {missing: key_terms - words}},
    {name: "conciseness", score: words.size <= expected[:max_words] ? 1.0 : 0.0}
  ]
end
```

`name` and `score` are required, `metadata` is optional.

See [multi_score.rb](./examples/eval/multi_score.rb) for a full example.

#### Trace scoring

Scorers can access the full evaluation trace (all spans generated by the task) by declaring a `trace:` keyword parameter. This is useful for inspecting intermediate LLM calls, validating tool usage, or checking the message thread:

```ruby
Braintrust::Eval.run(
  project: "my-project",
  cases: [{input: "What is 2+2?", expected: "4"}],
  task: Braintrust::Task.new { |input:| my_llm_pipeline(input) },
  scorers: [
    # Access the full trace to inspect LLM spans
    Braintrust::Scorer.new("uses_system_prompt") do |output:, trace:|
      messages = trace.thread  # reconstructed message thread from LLM spans
      messages.any? { |m| m["role"] == "system" } ? 1.0 : 0.0
    end,

    # Filter spans by type
    Braintrust::Scorer.new("single_llm_call") do |output:, trace:|
      trace.spans(span_type: "llm").length == 1 ? 1.0 : 0.0
    end,

    # Scorers without trace: still work — the parameter is filtered out automatically
    Braintrust::Scorer.new("exact_match") do |output:, expected:|
      output == expected ? 1.0 : 0.0
    end
  ]
)
```

See [trace_scoring.rb](./examples/eval/trace_scoring.rb) for a full example.

### Dev Server

Run evaluations from the Braintrust web UI against code in your own application.

#### Run as a Rack app

Define evaluators, pass them to the dev server, and start serving:

```ruby
# eval_server.ru
require "braintrust/eval"
require "braintrust/server"

# Define evaluators — these can reference your application code (models, services, etc.)
food_classifier = Braintrust::Eval::Evaluator.new(
  task: ->(input:) { FoodClassifier.classify(input) },
  scorers: [
    Braintrust::Scorer.new("exact_match") { |expected:, output:| output == expected ? 1.0 : 0.0 }
  ]
)

# Initialize Braintrust (requires BRAINTRUST_API_KEY)
Braintrust.init(blocking_login: true)

# Start the server
run Braintrust::Server::Rack.app(
  evaluators: {
    "food-classifier" => food_classifier
  }
)
```

Add your Rack server to your Gemfile:

```ruby
gem "rack"
gem "puma" # recommended
```

Then start the server:

```bash
bundle exec rackup eval_server.ru -p 8300 -o 0.0.0.0
```

See example: [server/eval.ru](./examples/server/eval.ru)

**Custom evaluators**

Evaluators can also be defined as subclasses:

```ruby
class FoodClassifier < Braintrust::Eval::Evaluator
  def task
    ->(input:) { classify(input) }
  end

  def scorers
    [Braintrust::Scorer.new("exact_match") { |expected:, output:| output == expected ? 1.0 : 0.0 }]
  end
end
```

#### Run as a Rails engine

Use the Rails engine when your evaluators live inside an existing Rails app and you want to mount the Braintrust eval server into that application.

Define each evaluator in its own file, for example under `app/evaluators/`:

```ruby
# app/evaluators/food_classifier.rb
class FoodClassifier < Braintrust::Eval::Evaluator
  def task
    ->(input:) { classify(input) }
  end

  def scorers
    [Braintrust::Scorer.new("exact_match") { |expected:, output:| output == expected ? 1.0 : 0.0 }]
  end
end
```

Then generate the Braintrust initializer:

```bash
bin/rails generate braintrust:eval_server
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Braintrust::Contrib::Rails::Engine, at: "/braintrust"
end
```

The generator writes `config/initializers/braintrust_server.rb`, where you can review or customize the slug-to-evaluator mapping it discovers from `app/evaluators/**/*.rb` and `evaluators/**/*.rb`.

See example: [contrib/rails/eval.rb](./examples/contrib/rails/eval.rb)

**Developing locally**

If you want to skip authentication on incoming eval requests while developing locally:

- **For Rack**: Pass `auth: :none` to `Braintrust::Server::Rack.app(...)`
- **For Rails**: Set `config.auth = :none` in `config/initializers/braintrust_server.rb`

*NOTE: Setting `:none` disables authentication on incoming requests into your server; executing evals requires a `BRAINTRUST_API_KEY` to fetch resources.*

**Supported web servers**

The dev server requires the `rack` gem and a Rack-compatible web server.

| Server                                         | Version Supported | Notes                                |
| ---------------------------------------------- | ----------------- | ------------------------------------ |
| [Puma](https://puma.io/)                       | 6.x               |                                      |
| [Falcon](https://socketry.github.io/falcon/)   | 0.x               |                                      |
| [Passenger](https://www.phusionpassenger.com/) | 6.x               |                                      |
| [WEBrick](https://github.com/ruby/webrick)     | Not supported     | Does not support server-sent events. |

See examples: [server/eval.ru](./examples/server/eval.ru), 

## Documentation

- [Braintrust Documentation](https://www.braintrust.dev/docs)
- [API Reference](https://gemdocs.org/gems/braintrust/)

## Troubleshooting

#### No traces after adding `require 'braintrust/setup'` to the Gemfile

First verify there are no errors in your logs after running with `BRAINTRUST_DEBUG=true` set.

Your application needs the following for this to work:

```ruby
require 'bundler/setup'
Bundler.require
```

It is present by default in Rails applications, but may not be in Sinatra, Rack, or other applications.

Alternatively, you can add `require 'braintrust/setup'` to your application initialization files.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup and guidelines.

## License

Apache License 2.0 - see [LICENSE](./LICENSE).
