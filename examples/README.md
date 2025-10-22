# Braintrust Ruby SDK Examples

This directory contains examples demonstrating how to use the Braintrust Ruby SDK.

## Prerequisites

All examples require a Braintrust API key. Get one from [Braintrust Settings](https://www.braintrust.dev/app/settings).

Set your API key as an environment variable:

```bash
export BRAINTRUST_API_KEY="your-api-key-here"
```

## Running Examples

From the project root:

```bash
# Run a specific example
ruby examples/login/login_basic.rb

# Enable debug logging
BRAINTRUST_DEBUG=true ruby examples/login/login_basic.rb
```

## Available Examples

### Login Examples

- **`login/login_basic.rb`**: Basic login example showing how to authenticate and retrieve organization information

## Coming Soon

- OpenTelemetry tracing examples
- OpenAI integration examples
- Eval framework examples
