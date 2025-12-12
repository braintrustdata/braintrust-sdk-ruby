# Milestone 09: RubyLLM Integration

## Goal

Port the RubyLLM integration to the new contrib framework.

## What You Get

All RubyLLM interactions auto-traced:

```ruby
require "braintrust"
Braintrust.init

# Using RubyLLM
chat = RubyLLM.chat(model: "gpt-4")
chat.ask("Hello!")  # Traced!
```

## Success Criteria

- `Braintrust::Contrib::RubyLLM::Integration.patch!` instruments RubyLLM
- Class-level patching
- Existing behavior preserved
- All existing RubyLLM tests pass

## Files to Create

### `lib/braintrust/contrib/ruby_llm/integration.rb`

```ruby
# lib/braintrust/contrib/ruby_llm/integration.rb
require_relative "../integration"

module Braintrust
  module Contrib
    module RubyLLM
      class Integration
        include Braintrust::Contrib::Integration

        def self.integration_name
          :ruby_llm
        end

        def self.gem_names
          ["ruby_llm"]
        end

        def self.require_paths
          ["ruby_llm"]
        end

        def self.minimum_version
          "1.0.0"
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

### `lib/braintrust/contrib/ruby_llm/patcher.rb`

```ruby
# lib/braintrust/contrib/ruby_llm/patcher.rb
require_relative "../patcher"

module Braintrust
  module Contrib
    module RubyLLM
      class Patcher < Braintrust::Contrib::Patcher
        class << self
          def perform_patch(context)
            patch_chat
          end

          private

          def patch_chat
            ::RubyLLM::Chat.prepend(ChatPatch)
          end
        end

        module ChatPatch
          def ask(message, **options)
            Braintrust::Trace.traced(name: "RubyLLM Chat", type: "llm") do |span|
              # Tracing logic refactored from existing ruby_llm.rb
              super
            end
          end
        end
      end
    end
  end
end
```

## Files to Modify

### `lib/braintrust/contrib.rb`

Add require for RubyLLM integration stub and register it:

```ruby
require_relative "contrib/ruby_llm/integration"

# Register the integration
Contrib::RubyLLM::Integration.register!
```

**Note:** Registration is explicit in `contrib.rb` rather than automatic in the integration file, following the pattern established in Milestone 02.

### `lib/braintrust/contrib/ruby_llm.rb`

Add per-client `instrument!` method (the new API):

```ruby
# lib/braintrust/contrib/ruby_llm.rb
module Braintrust
  module Contrib
    module RubyLLM
      # Instrument a specific client instance
      # This is the new API; Braintrust::Trace::RubyLLM.wrap is the backwards-compat alias
      def self.instrument!(client)
        # Same behavior as the existing wrap() function
        # ... wrapping logic ...
        client
      end
    end
  end
end
```

### `lib/braintrust/trace/contrib/ruby_llm.rb`

Convert to compatibility shim that delegates to new API:

```ruby
# lib/braintrust/trace/contrib/ruby_llm.rb
# Backwards compatibility - delegates to new contrib framework

module Braintrust
  module Trace
    module RubyLLM
      def self.wrap(client)
        Braintrust::Contrib::RubyLLM.instrument!(client)
      end
    end
  end
end
```

## Tests to Create

### `test/braintrust/contrib/ruby_llm/integration_test.rb`

- Test `integration_name`, `gem_names`, `require_paths`
- Test `available?` and `compatible?`
- Test `patch!` calls patcher

### `test/braintrust/contrib/ruby_llm/patcher_test.rb`

- Test class-level patching (new instances are instrumented)
- Test idempotency (patch! twice doesn't double-wrap)
- Test `applicable?` returns true for this patcher
- Test `ask` method is traced

## Documentation

Update README to show RubyLLM in list of supported libraries.

## Dependencies

- [01-core-infrastructure.md](01-core-infrastructure.md) must be complete
