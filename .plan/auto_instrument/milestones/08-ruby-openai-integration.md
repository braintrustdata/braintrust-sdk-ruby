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

Both the official `openai` gem and `ruby-openai` gem use the `OpenAI` namespace. The integration must:

1. Detect which gem is actually loaded
2. Only patch if `ruby-openai` is loaded (not official `openai`)
3. Use different require paths for auto-instrument detection

```ruby
def self.gem_names
  ["ruby-openai"]  # Different from official "openai" gem
end

def self.require_paths
  ["openai"]  # Same require path, but gem_names disambiguates
end

def self.available?
  # Must be ruby-openai specifically, not official openai gem
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

        # Override available? to check for ruby-openai specifically
        def self.available?
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

Braintrust::Contrib::RubyOpenai::Integration.register!
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

Add require for ruby-openai integration stub:

```ruby
require_relative "contrib/ruby_openai/integration"
```

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

- Test gem detection (ruby-openai vs official openai)
- Test `available?` returns correct value

### `test/braintrust/contrib/ruby_openai/patcher_test.rb`

Same test patterns as other integrations.

## Documentation

Update README to clarify:
- Difference between `openai` and `ruby-openai` gems
- Both are supported
- Auto-detection handles the right one

## Dependencies

- [01-core-infrastructure.md](01-core-infrastructure.md) must be complete
- [02-openai-integration.md](02-openai-integration.md) must be complete (for disambiguation)
