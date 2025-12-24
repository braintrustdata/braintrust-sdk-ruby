# Braintrust Ruby SDK Examples

This directory contains examples demonstrating how to use the Braintrust Ruby SDK.

## Prerequisites

All examples require a Braintrust API key. Get one from [Braintrust Settings](https://www.braintrust.dev/app/settings).

Set your API key as an environment variable:

```bash
export BRAINTRUST_API_KEY="your-api-key-here"
```

## Running Examples

### Using Rake (Recommended)

The rake task automatically uses the correct gemfile for each example:

```bash
# Run a single example
rake 'example[examples/trace/multiple_projects.rb]'

# Run all examples
rake examples
```

### Running Directly

From the project root:

```bash
# Run a specific example
ruby examples/login.rb

# Enable debug logging
BRAINTRUST_DEBUG=true ruby examples/login.rb
```

## Available Examples

### Login Examples

- **`login.rb`**: Basic login example showing how to authenticate and retrieve organization information


### Tracing Examples

- **`trace.rb`**: Basic OpenTelemetry tracing example
- **`trace/span_filtering.rb`**: Example of filtering out non-AI spans in traces to reduce noise
- **`trace/trace_attachments.rb`**: Example of adding attachments (images, PDFs, BLOBs) to traces
- **`trace/multiple_projects.rb`**: Example of logging traces to multiple Braintrust projects simultaneously

### LLM Integration Examples

- **`openai.rb`**: OpenAI integration example
- **`anthropic.rb`**: Anthropic integration example
- **`ruby_llm.rb`**: Ruby LLM integration example
- **`alexrudall_openai.rb`**: Alexrudall's ruby-openai gem integration example

### Evaluation Examples

- **`eval.rb`**: Defining scorers and running evals
- **`eval/dataset.rb`**: Running an evaluation against a dataset
- **`eval/remote_functions.rb`**: Using remote functions (server-side prompts) in evaluations

### API Examples

- **`api/dataset.rb`**: Dataset API usage example
