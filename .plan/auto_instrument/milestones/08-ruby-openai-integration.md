# Milestone 08: Ruby-OpenAI Integration

## Goal

Port the ruby-openai (alexrudall/ruby-openai) integration to the new contrib framework.

## What You Get

All ruby-openai clients auto-traced:

```ruby
require "braintrust"
Braintrust.init

# Using alexrudall/ruby-openai gem
client = OpenAI::Client.new(access_token: "...")
client.chat(parameters: { ... })  # Traced!
```

## Success Criteria

- `Braintrust::Contrib::RubyOpenai::Integration.patch!` instruments ruby-openai clients
- Handles namespace collision with official `openai` gem
- Class-level patching (new instances are auto-traced)
- Existing `.wrap(client)` API still works
- All existing ruby-openai tests pass

## Important: Gem Disambiguation

Both the official `openai` gem and `ruby-openai` gem use the `OpenAI` namespace and the same require path (`"openai"`). Both gems can be installed simultaneously, but only one's code can be loaded.

### Detection Strategy

Check `$LOADED_FEATURES` to determine which gem's code was actually loaded (both can be in `Gem.loaded_specs`, but only one loads code):

```ruby
def self.gem_names
  ["ruby-openai"]
end

def self.require_paths
  ["openai"]  # Same as official gem
end

# Override available? to check which gem's code is actually loaded
def self.available?
  $LOADED_FEATURES.any? { |f| f.end_with?("/openai.rb") && f.include?("ruby-openai") } ||
    Gem.loaded_specs.key?("ruby-openai")
end
```

## Files to Create

### `lib/braintrust/contrib/ruby_openai/integration.rb`

```ruby
# lib/braintrust/contrib/ruby_openai/integration.rb
require_relative "../integration"

module Braintrust
  module Contrib
    module RubyOpenai
      class Integration
        include Braintrust::Contrib::Integration

        def self.integration_name
          :ruby_openai
        end

        def self.gem_names
          ["ruby-openai"]
        end

        def self.require_paths
          ["openai"]  # Same require path as official gem
        end

        def self.minimum_version
          "3.0.0"
        end

        # Override available? to check which gem's code is actually loaded
        def self.available?
          $LOADED_FEATURES.any? { |f| f.end_with?("/openai.rb") && f.include?("ruby-openai") } ||
            Gem.loaded_specs.key?("ruby-openai")
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

### `lib/braintrust/contrib/ruby_openai/patcher.rb`

```ruby
# lib/braintrust/contrib/ruby_openai/patcher.rb
require_relative "../patcher"

module Braintrust
  module Contrib
    module RubyOpenai
      class Patcher < Braintrust::Contrib::Patcher
        class << self
          def perform_patch(context)
            patch_chat
          end

          private

          def patch_chat
            ::OpenAI::Client.prepend(ChatPatch)
          end
        end

        module ChatPatch
          def chat(parameters: {})
            Braintrust::Trace.traced(name: "OpenAI Chat", type: "llm") do |span|
              # Tracing logic refactored from existing code
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

Add require for ruby-openai integration stub and register it:

```ruby
require_relative "contrib/ruby_openai/integration"

# Register the integration
Contrib::RubyOpenai::Integration.register!
```

**Note:** Registration is explicit in `contrib.rb` rather than automatic in the integration file, following the pattern established in Milestone 02.

### `lib/braintrust/contrib/ruby_openai.rb`

Add per-client `instrument!` method (the new API):

```ruby
# lib/braintrust/contrib/ruby_openai.rb
module Braintrust
  module Contrib
    module RubyOpenai
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

The existing shim needs to detect which gem is loaded and delegate appropriately:

```ruby
# lib/braintrust/trace/contrib/openai.rb
# Backwards compatibility - delegates to new contrib framework

module Braintrust
  module Trace
    module OpenAI
      def self.wrap(client)
        # Detect which gem is loaded and delegate to appropriate integration
        if Gem.loaded_specs.key?("ruby-openai")
          Braintrust::Contrib::RubyOpenai.instrument!(client)
        else
          Braintrust::Contrib::OpenAI.instrument!(client)
        end
      end
    end
  end
end
```

## Tests to Create

### `test/braintrust/contrib/ruby_openai/integration_test.rb`

- Test `integration_name`, `gem_names`, `require_paths`
- Test `available?` correctly detects ruby-openai gem (not official openai)
- Test `available?` checks $LOADED_FEATURES for gem disambiguation
- Test `available?` returns false when only official openai gem is loaded
- Test `compatible?`
- Test `patch!` calls patcher

### `test/braintrust/contrib/ruby_openai/patcher_test.rb`

- Test class-level patching (new clients are instrumented)
- Test idempotency (patch! twice doesn't double-wrap)
- Test `applicable?` returns true for this patcher
- Test `chat` method is traced

## Documentation

Update README to clarify:
- Difference between `openai` and `ruby-openai` gems
- Both are supported
- Auto-detection handles the right one

## Dependencies

- [01-core-infrastructure.md](01-core-infrastructure.md) must be complete
- [02-openai-integration.md](02-openai-integration.md) must be complete (for disambiguation)

## Optional: Shared Utilities Refactoring

**Consider** performing the shared utilities refactoring described in [ref/future-work.md](../ref/future-work.md#shared-utilities-refactoring) during this milestone.

**Why this milestone?** By this point, you'll have:
- Multiple integrations (official openai, ruby-openai, possibly anthropic)
- Better understanding of what utilities are truly shared vs vendor-specific
- Real patterns emerged from implementation

**What to refactor:**
- Move token parsing from `lib/braintrust/trace/tokens.rb` to `lib/braintrust/contrib/support/openai.rb` and `support/anthropic.rb`
- Extract shared utilities from patcher files to appropriate `support/` files
- Add backward compatibility layer in old locations

**Decision point:** If this milestone feels too large with the refactoring, defer it to a dedicated "cleanup" milestone after all initial integrations are ported.
