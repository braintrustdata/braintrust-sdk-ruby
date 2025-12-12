# Milestone 07: Anthropic Integration

## Goal

Port the Anthropic integration to the new contrib framework.

## What You Get

All Anthropic clients auto-traced:

```ruby
require "braintrust"
Braintrust.init

client = Anthropic::Client.new
client.messages.create(...)  # Traced!
```

## Success Criteria

- `Braintrust::Contrib::Anthropic::Integration.patch!` instruments all Anthropic clients
- Class-level patching (new instances are auto-traced)
- Existing `.wrap(client)` API still works (backwards compatible)
- All existing Anthropic tests pass

## Files to Create

### `lib/braintrust/contrib/anthropic/integration.rb`

```ruby
# lib/braintrust/contrib/anthropic/integration.rb
require_relative "../integration"

module Braintrust
  module Contrib
    module Anthropic
      class Integration
        include Braintrust::Contrib::Integration

        def self.integration_name
          :anthropic
        end

        def self.gem_names
          ["anthropic"]
        end

        def self.require_paths
          ["anthropic"]
        end

        def self.minimum_version
          "0.1.0"
        end

        def self.patcher
          require_relative "patcher"
          Patcher
        end
      end
    end
  end
end
```

### `lib/braintrust/contrib/anthropic/patcher.rb`

```ruby
# lib/braintrust/contrib/anthropic/patcher.rb
require_relative "../patcher"

module Braintrust
  module Contrib
    module Anthropic
      class Patcher < Braintrust::Contrib::Patcher
        class << self
          def perform_patch(context)
            patch_messages
          end

          private

          def patch_messages
            ::Anthropic::Client.prepend(MessagesPatch)
          end
        end

        module MessagesPatch
          def messages
            messages_resource = super
            unless messages_resource.singleton_class.ancestors.include?(MessagesWrapper)
              messages_resource.singleton_class.prepend(MessagesWrapper)
            end
            messages_resource
          end
        end

        module MessagesWrapper
          def create(parameters: {})
            Braintrust::Trace.traced(name: "Anthropic Messages", type: "llm") do |span|
              # Tracing logic refactored from existing anthropic.rb
              super
            end
          end

          # Also wrap streaming methods
        end
      end
    end
  end
end
```

## Files to Modify

### `lib/braintrust/contrib.rb`

Add require for Anthropic integration stub and register it:

```ruby
require_relative "contrib/anthropic/integration"

# Register the integration
Contrib::Anthropic::Integration.register!
```

**Note:** Registration is explicit in `contrib.rb` rather than automatic in the integration file, following the pattern established in Milestone 02.

### `lib/braintrust/contrib/anthropic.rb`

Add per-client `instrument!` method (the new API):

```ruby
# lib/braintrust/contrib/anthropic.rb
module Braintrust
  module Contrib
    module Anthropic
      # Instrument a specific client instance
      # This is the new API; Braintrust::Trace::Anthropic.wrap is the backwards-compat alias
      def self.instrument!(client)
        # Same behavior as the existing wrap() function
        # ... wrapping logic ...
        client
      end
    end
  end
end
```

### `lib/braintrust/trace/contrib/anthropic.rb`

Convert to compatibility shim that delegates to new API:

```ruby
# lib/braintrust/trace/contrib/anthropic.rb
# Backwards compatibility - delegates to new contrib framework

module Braintrust
  module Trace
    module Anthropic
      def self.wrap(client)
        Braintrust::Contrib::Anthropic.instrument!(client)
      end
    end
  end
end
```

## Tests to Create

### `test/braintrust/contrib/anthropic/integration_test.rb`

- Test `integration_name`, `gem_names`, `require_paths`
- Test `available?` and `compatible?`
- Test `patch!` calls patcher

### `test/braintrust/contrib/anthropic/patcher_test.rb`

- Test class-level patching (new clients are instrumented)
- Test idempotency (patch! twice doesn't double-wrap)
- Test `applicable?` returns true for this patcher
- Test `messages.create` is traced
- Test streaming methods are traced

## Documentation

Update README to show Anthropic in list of supported libraries.

## Dependencies

- [01-core-infrastructure.md](01-core-infrastructure.md) must be complete
- [02-openai-integration.md](02-openai-integration.md) recommended (establishes patterns)
