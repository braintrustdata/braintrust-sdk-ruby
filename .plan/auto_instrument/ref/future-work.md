# Future Work

Potential enhancements beyond the core auto-instrumentation milestones. These are ideas for future iterations, not committed work.

## Core-Only Require

Add `lib/braintrust/core.rb` for users who want minimal footprint without contrib overhead:

```ruby
require "braintrust/core"  # Just core (State, Config, Trace, API, Eval)
# No integrations loaded - smaller memory footprint
```

Useful for:
- Applications that don't use any supported LLM libraries
- Custom instrumentation scenarios
- Reducing startup time

When implemented, `braintrust.rb` would become:
```ruby
require_relative "braintrust/core"
require_relative "braintrust/contrib"
```

## Per-Integration Configuration

Add a `Configuration` class hierarchy for integration-specific settings.

Configuration values could be derived from multiple sources (in priority order):
1. Programmatic configuration via `configure` block
2. Environment variables (e.g., `BRAINTRUST_OPENAI_INCLUDE_PROMPTS=false`)
3. Configuration file (e.g., `.braintrust.yml`)

```ruby
# lib/braintrust/contrib/configuration.rb
class Configuration
  attr_accessor :enabled  # default: true
end

# lib/braintrust/contrib/openai/configuration.rb
class Configuration < Braintrust::Contrib::Configuration
  attr_accessor :trace_chat_completions  # default: true
  attr_accessor :trace_responses         # default: true
  attr_accessor :include_prompts         # default: true (for privacy control)
end
```

Usage:
```ruby
Braintrust::Contrib::OpenAI::Integration.configure do |config|
  config.include_prompts = false  # Don't log prompts for privacy
end
```

## Instance-Level Configuration (Pin)

Allow per-instance configuration, similar to Datadog's `Pin` class:

```ruby
client = OpenAI::Client.new
Braintrust::Contrib.pin(client, service_name: "my-openai-service")
```

This would allow:
- Different tracing settings per client instance
- Service name customization
- Selective enable/disable on specific instances

## Span Filtering by Integration

Allow filtering spans based on integration type or other criteria:

```ruby
Braintrust.configure do |config|
  config.span_filter = ->(span) {
    # Drop spans from specific integrations
    span.integration != :ruby_llm
  }
end
```

## Metrics Collection

Aggregate metrics across integrations:
- Total tokens used
- Latency percentiles
- Error rates by integration
- Cost estimates

```ruby
Braintrust::Contrib.metrics
# => { openai: { requests: 100, tokens: 50000, avg_latency_ms: 250 }, ... }
```

## Additional Integrations

Potential future integrations:
- **Cohere** - Cohere API client
- **AI21** - AI21 Labs API client
- **Mistral** - Mistral AI client
- **LangChain.rb** - LangChain Ruby framework
- **Instructor-rb** - Structured extraction library

## Unpatch Support

Allow removing instrumentation:

```ruby
Braintrust::Contrib::OpenAI::Integration.unpatch!
```

This is complex because:
- Ruby doesn't have clean "unprepend"
- Would need to track original methods
- May not be worth the complexity
