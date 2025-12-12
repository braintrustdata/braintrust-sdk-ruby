# Braintrust Ruby SDK: Auto-Instrumentation

Make it fast and easy to get your application instrumented.

## The Problem

Today, instrumenting LLM libraries requires manual setup per client:

```ruby
require "braintrust"
Braintrust.init

client = OpenAI::Client.new
Braintrust::Trace::OpenAI.wrap(client)  # Must wrap every client instance

client2 = Anthropic::Client.new
Braintrust::Trace::Anthropic.wrap(client2)  # And again for each library...
```

This is verbose, error-prone, and easy to forget.

## The Vision

**It just works.** One line, all libraries instrumented:

```ruby
require "braintrust"
Braintrust.init  # That's it. All OpenAI/Anthropic/etc clients auto-traced.
```

Or even zero lines with CLI:
```bash
braintrust exec -- ruby app.rb
```

## Benefits

| Benefit         | Description                                      |
| --------------- | ------------------------------------------------ |
| **Zero-config** | Works out of the box with sensible defaults      |
| **Safe**        | Fails gracefully; never breaks user applications |
| **Flexible**    | Opt-out or selective instrumentation when needed |
| **CLI support** | Instrument without any code changes              |

## User Experience

Not all applications and environments are the same. We provide several ways to instrument applications, ordered from most automatic to most customizable.

### 1. Zero Code

**Best for:** Instrumenting any Ruby application without modifying its code.

```bash
braintrust exec -- ruby app.rb
braintrust exec -- bundle exec rails s
```

### 2. Zero Config

**Best for:** Instrumenting specific Ruby applications with smart defaults and maximum compatibility.

```ruby
# Gemfile
gem "braintrust", require: "braintrust/contrib/auto_instrument"

# Or Rails initializer
require "braintrust/contrib/auto_instrument"
```

### 3. Single Line

**Best for:** Controlling when and what instrumentation is activated.

```ruby
require "braintrust"

Braintrust.init # Auto-instruments all detected libraries

client = OpenAI::Client.new
client.chat.completions.create(...)  # Automatically traced!
```

You can also choose what instrumentation is activated:

```ruby
# You can set environment variables:
#
#   BRAINTRUST_AUTO_INSTRUMENT=true
#   BRAINTRUST_INSTRUMENT_ONLY=openai,anthropic
#   BRAINTRUST_INSTRUMENT_EXCEPT=ruby_llm
#

# Or configure explicitly in code:
Braintrust.init(auto_instrument: { only: [:openai, :anthropic] })  # Only specific libraries
# --- OR ---
Braintrust.init(auto_instrument: { except: [:ruby_llm] })  # Exclude certain libraries

client = OpenAI::Client.new
client.chat.completions.create(...)  # Automatically traced!
```

### 4. Custom

**Best for:** Fine-control over which parts of an application are instrumented.

```ruby
# Skip auto-instrument with:
#
#   BRAINTRUST_AUTO_INSTRUMENT=false
#
# Or configure explicitly in code:
Braintrust.init(auto_instrument: false)

# ...then manually instrument a specific OpenAI client
client = OpenAI::Client.new
Braintrust::Contrib::OpenAI.instrument!(client)  # Explicit per-client wrapping
```

## Milestones

| #                                                   | Milestone                    | What You Get                                                                      |
| --------------------------------------------------- | ---------------------------- | --------------------------------------------------------------------------------- |
| [01](milestones/01-integration-framework.md)        | Integration framework        | Consistent interface across integrations (for more reliable auto-instrumentation) |
| [02](milestones/02-openai-integration.md)           | OpenAI Integration           | All OpenAI clients auto-traced with `Integration.patch!`                          |
| [03](milestones/03-instrument-api.md)               | Instrument API               | Clean `Braintrust::Contrib.instrument!(:openai)` call                             |
| [04](milestones/04-init-auto-instrument.md)         | Init Auto-Instrument         | `Braintrust.init` auto-instruments everything (zero-config)                       |
| [05](milestones/05-require-time-auto-instrument.md) | Require-time Auto-Instrument | Works via `Gemfile` or Rails initializer (no `init()` needed)                     |
| [06](milestones/06-cli-wrapper.md)                  | CLI Wrapper                  | `braintrust exec -- ruby app.rb` (zero code changes)                              |
| [07](milestones/07-anthropic-integration.md)        | Anthropic Integration        | Anthropic clients auto-traced                                                     |
| [08](milestones/08-ruby-openai-integration.md)      | Ruby-OpenAI Integration      | alexrudall/ruby-openai gem auto-traced                                            |
| [09](milestones/09-ruby-llm-integration.md)         | RubyLLM Integration          | RubyLLM auto-traced                                                               |

## See Also

- [Technical Design](ref/design.md) - Architecture, principles, and implementation details
- [Future Work](ref/future-work.md) - Potential next steps beyond the core milestones
