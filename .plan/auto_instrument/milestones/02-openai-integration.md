# Milestone 02: OpenAI Integration

## Goal

First working integration as proof of concept, demonstrating the contrib framework with class-level patching.

## What You Get

All OpenAI clients auto-traced with `Braintrust::Contrib::OpenAI::Integration.patch!`

```ruby
require "braintrust"
Braintrust.init

# Explicitly patch OpenAI (auto-instrument comes in later milestones)
Braintrust::Contrib::OpenAI::Integration.patch!

# All clients now auto-traced
client = OpenAI::Client.new
client.chat.completions.create(...)  # Traced!
```

## Success Criteria

- `Braintrust::Contrib::OpenAI::Integration.patch!` instruments all OpenAI clients
- Class-level patching (new instances are auto-traced)
- Idempotent (calling patch! twice doesn't double-wrap)
- Existing `.wrap(client)` API still works (backwards compatible)
- All existing OpenAI tests pass

## Files to Create

### `lib/braintrust/contrib/openai/integration.rb`

Stub file with minimal metadata (eager loaded):

```ruby
# lib/braintrust/contrib/openai/integration.rb
require_relative "../integration"

module Braintrust
  module Contrib
    module OpenAI
      class Integration
        include Braintrust::Contrib::Integration

        def self.integration_name
          :openai
        end

        def self.gem_names
          ["openai"]  # Official openai gem only
        end

        def self.require_paths
          ["openai"]
        end

        def self.minimum_version
          "0.1.0"
        end

        # Override available? to distinguish from ruby-openai gem
        def self.available?
          $LOADED_FEATURES.any? { |f| f.end_with?("/openai.rb") && f.include?("/openai-") } ||
            Gem.loaded_specs.key?("openai")
        end

        # Lazy-load the patcher only when actually patching
        def self.patcher
          require_relative "patcher"
          Patcher
        end
      end
    end
  end
end
```

### `lib/braintrust/contrib/openai/patcher.rb`

Heavy file with patching logic (lazy loaded):

```ruby
# lib/braintrust/contrib/openai/patcher.rb
require_relative "../patcher"

module Braintrust
  module Contrib
    module OpenAI
      class Patcher < Braintrust::Contrib::Patcher
        class << self
          def perform_patch(context)
            patch_chat_completions
            patch_responses if responses_available?
          end

          private

          def patch_chat_completions
            # Patch at class level - affects all future instances
            ::OpenAI::Client.prepend(ChatCompletionsPatch)
          end

          def patch_responses
            ::OpenAI::Client.prepend(ResponsesPatch)
          end

          def responses_available?
            defined?(::OpenAI::Client) &&
              ::OpenAI::Client.instance_methods.include?(:responses)
          end
        end

        # Module to prepend to OpenAI::Client for chat.completions
        module ChatCompletionsPatch
          def chat
            chat_resource = super
            unless chat_resource.completions.singleton_class.ancestors.include?(CompletionsWrapper)
              chat_resource.completions.singleton_class.prepend(CompletionsWrapper)
            end
            chat_resource
          end
        end

        # Module to prepend to chat.completions
        module CompletionsWrapper
          def create(parameters: {})
            # Tracing logic here - refactored from existing openai.rb
            Braintrust::Trace.traced(name: "OpenAI Chat Completion", type: "llm") do |span|
              # ... span attributes, metrics, etc.
              super
            end
          end

          # Also wrap stream, stream_raw methods
        end

        # Module for responses API (if available)
        module ResponsesPatch
          # Similar pattern for responses.create
        end
      end
    end
  end
end
```

**Note:** The actual patcher implementation will be refactored from the existing `lib/braintrust/trace/contrib/openai.rb` code. The wrapper modules will reuse the span creation, aggregation, and metrics logic already implemented.

## Files to Modify

### `lib/braintrust/contrib.rb`

Add require for OpenAI integration stub:

```ruby
# Load integration stubs (eager load minimal metadata)
require_relative "contrib/openai/integration"

# Register the integration
Contrib::OpenAI::Integration.register!
```

**Note:** Registration is explicit in `contrib.rb` rather than automatic in the integration file. This allows integrations to be loaded without side effects, which is useful for testing and tooling that may want to inspect integrations without registering them globally.

### `lib/braintrust/contrib/openai.rb`

Add per-client `instrument!` method (the new API):

```ruby
# lib/braintrust/contrib/openai.rb
module Braintrust
  module Contrib
    module OpenAI
      # Instrument a specific client instance
      # This is the new API; Braintrust::Trace::OpenAI.wrap is the backwards-compat alias
      def self.instrument!(client)
        # Same behavior as the existing wrap() function
        # ... wrapping logic ...
        client
      end
    end
  end
end
```

### `lib/braintrust/trace/contrib/openai.rb`

Convert to compatibility shim that delegates to new API:

```ruby
# lib/braintrust/trace/contrib/openai.rb
# Backwards compatibility - delegates to new contrib framework

module Braintrust
  module Trace
    module OpenAI
      def self.wrap(client)
        Braintrust::Contrib::OpenAI.instrument!(client)
      end
    end
  end
end
```

### `lib/braintrust/trace.rb`

Remove direct require of `trace/contrib/openai.rb` (it's now loaded via contrib):

```ruby
# Remove: require_relative "trace/contrib/openai"
```

## Tests to Create/Update

### `test/braintrust/contrib/openai/integration_test.rb`

- Test `integration_name`, `gem_names`, `require_paths`
- Test `available?` correctly detects official openai gem (not ruby-openai)
- Test `available?` checks $LOADED_FEATURES for gem disambiguation
- Test `compatible?`
- Test `patch!` calls patcher

### `test/braintrust/contrib/openai/patcher_test.rb`

- Test class-level patching (new clients are instrumented)
- Test idempotency (patch! twice doesn't double-wrap)
- Test `applicable?` returns true for this patcher
- Test `chat.completions.create` is traced
- Test streaming methods are traced

### `test/braintrust/trace/openai_test.rb` (existing)

- Verify existing tests still pass
- Add tests for `.wrap()` compatibility shim

## Documentation

Add example usage to README showing explicit `patch!` call.

## Dependencies

- [01-core-infrastructure.md](01-core-infrastructure.md) must be complete

## Notes

### Existing Clients Not Patched

Class-level patching only affects clients created *after* patching occurs. Clients instantiated before `patch!` is called will not be instrumented. This is documented as expected behavior.

### Refactoring Existing Code

The bulk of the work is refactoring existing `trace/contrib/openai.rb` logic into the new patcher structure. The tracing logic itself doesn't change - just where it lives and how it's activated.
