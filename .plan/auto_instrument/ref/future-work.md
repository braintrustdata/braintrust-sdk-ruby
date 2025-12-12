# Future Work

Potential enhancements beyond the core auto-instrumentation milestones. These are ideas for future iterations, not committed work.

## Shared Utilities Refactoring

**When:** During Milestone 08 (ruby-openai integration) or later
**Status:** Planned - shelved until multiple integrations exist

### Current State

Integration support utilities are scattered:
- Token parsing: `lib/braintrust/trace/tokens.rb` (parse_openai_usage_tokens, parse_anthropic_usage_tokens)
- Per-integration utilities: Embedded in patcher files (e.g., `lib/braintrust/contrib/openai/patcher.rb`)

This creates:
- Confusion about where utilities live (`trace/` vs `contrib/`)
- Difficulty discovering what utilities exist for each vendor
- Unclear ownership and boundaries

### Proposed Structure

Organize shared utilities by **vendor** under `lib/braintrust/contrib/support/`:

```ruby
lib/braintrust/contrib/support/
  openai.rb                 # module Braintrust::Contrib::Support::OpenAI
  anthropic.rb              # module Braintrust::Contrib::Support::Anthropic
  common.rb                 # module Braintrust::Contrib::Support::Common (optional)
```

Each vendor file contains utilities specific to that provider's API:

```ruby
# lib/braintrust/contrib/support/openai.rb
module Braintrust::Contrib::Support::OpenAI
  def self.parse_usage_tokens(usage)
    # OpenAI-specific token field parsing
  end

  def self.aggregate_streaming_chunks(chunks)
    # OpenAI-specific streaming aggregation
  end
end
```

Truly generic utilities (if they emerge) go in `common.rb`:

```ruby
# lib/braintrust/contrib/support/common.rb
module Braintrust::Contrib::Support::Common
  def self.set_json_attr(span, attr_name, obj)
    # Generic span attribute helper
  end
end
```

### Rationale for Vendor-Based Organization

**Why by vendor instead of by behavior?**

- **Isolation**: Changes to OpenAI utilities don't touch Anthropic files
- **Clear ownership**: All OpenAI-specific logic in one place
- **Matches reality**: Token parsing isn't shared code - each vendor has different response structures
- **Aligns with integration structure**: Integrations are organized by vendor (`contrib/openai/`, `contrib/anthropic/`)
- **Easy cleanup**: Remove a vendor? Delete one file
- **Room to grow**: If a vendor file exceeds ~200 lines, refactor to a subdirectory

**Alternatives considered:**
- Organize by behavior (`support/token_parsing.rb` with all vendors) - rejected due to vendor coupling and large file growth
- Hybrid with base classes - rejected as over-engineering for current needs

### Migration Strategy

1. **Create vendor support files** with utilities extracted from current locations
2. **Update integrations** to require and use new locations:
   ```ruby
   require_relative "../support/openai"

   metrics = Braintrust::Contrib::Support::OpenAI.parse_usage_tokens(usage)
   ```
3. **Add backward compatibility** in `lib/braintrust/trace/tokens.rb`:
   ```ruby
   require_relative "../contrib/support/openai"

   module Braintrust::Trace
     def self.parse_openai_usage_tokens(usage)
       Contrib::Support::OpenAI.parse_usage_tokens(usage)
     end
   end
   ```
4. **Deprecate old location** (optional) after all internal usage migrated

### Files to Move

From `lib/braintrust/trace/tokens.rb`:
- `parse_openai_usage_tokens` → `contrib/support/openai.rb`
- `parse_anthropic_usage_tokens` → `contrib/support/anthropic.rb`

From `lib/braintrust/contrib/openai/patcher.rb`:
- `set_json_attr` → Consider for `contrib/support/common.rb`
- `aggregate_streaming_chunks` → `contrib/support/openai.rb`
- `aggregate_responses_events` → `contrib/support/openai.rb`

### Benefits

- **Clearer architecture**: Support utilities live with integrations, not in `trace/`
- **Better discoverability**: "What utilities exist for OpenAI?" → Look in `support/openai.rb`
- **Reduced coupling**: Vendor changes isolated
- **Consistent patterns**: Matches how integrations are already organized

## System-level auto instrument

Users install a system package (e.g. `.deb`, `.sh` script) or similar that injects the Braintrust SDK into all Ruby applications on the system.

The technical idea is to modify the Ruby system configuration to always load Braintrust with any Ruby process.

Useful for:

- *Containerized deployments* by baking the Braintrust SDK into user's Docker image build step in their CI/CD pipelines
- *Host-based deployments* when Ruby apps installed directly onto the host.

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
