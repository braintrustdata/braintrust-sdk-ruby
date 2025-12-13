# Milestone 03: Instrument API

## Goal

Provide a clean public API for explicitly instrumenting specific integrations.

## What You Get

Clean `Braintrust::Contrib.instrument!` method for selective instrumentation:

```ruby
require "braintrust"
Braintrust.init

# Instrument specific integrations
Braintrust::Contrib.instrument!(:openai)

# Or instrument all available
Braintrust::Contrib.instrument!

# With filtering
Braintrust::Contrib.instrument!(only: [:openai, :anthropic])
Braintrust::Contrib.instrument!(except: [:ruby_llm])
```

## Success Criteria

- `Braintrust::Contrib.instrument!` patches specified integrations
- Support for `only:` and `except:` filtering
- Returns hash of results `{ openai: true, anthropic: false, ... }`
- Idempotent (calling twice is safe)

## Files to Modify

### `lib/braintrust/contrib.rb`

Add `instrument!` method:

```ruby
# lib/braintrust/contrib.rb
require_relative "contrib/registry"
require_relative "contrib/integration"
require_relative "contrib/patcher"

module Braintrust
  module Contrib
    class << self
      def registry
        Registry.instance
      end

      # Instrument integrations
      #
      # @param integrations [Array<Symbol>] specific integrations to instrument (optional)
      # @param only [Array<Symbol>] whitelist of integrations
      # @param except [Array<Symbol>] blacklist of integrations
      # @return [Hash<Symbol, Boolean>] results per integration
      #
      # @example Instrument all available
      #   Braintrust::Contrib.instrument!
      #
      # @example Instrument specific integrations
      #   Braintrust::Contrib.instrument!(:openai, :anthropic)
      #
      # @example With filtering
      #   Braintrust::Contrib.instrument!(only: [:openai])
      #   Braintrust::Contrib.instrument!(except: [:ruby_llm])
      #
      def instrument!(*integrations, only: nil, except: nil)
        # If specific integrations provided, use those
        if integrations.any?
          targets = integrations.map { |name| registry[name] }.compact
        else
          targets = registry.available
        end

        # Apply filters
        if only
          only_syms = Array(only).map(&:to_sym)
          targets = targets.select { |i| only_syms.include?(i.integration_name) }
        end

        if except
          except_syms = Array(except).map(&:to_sym)
          targets = targets.reject { |i| except_syms.include?(i.integration_name) }
        end

        # Patch each and collect results
        results = {}
        targets.each do |integration|
          results[integration.integration_name] = integration.patch!
        end
        results
      end
    end
  end
end

# Load integration stubs
require_relative "contrib/openai/integration"
```

### `lib/braintrust/contrib/registry.rb`

Add `instrument!` method to registry (delegates to module method but available on registry too):

```ruby
# Add to Registry class
def instrument!(only: nil, except: nil)
  targets = available
  targets = targets.select { |i| only.include?(i.integration_name) } if only
  targets = targets.reject { |i| except.include?(i.integration_name) } if except

  results = {}
  targets.each do |integration|
    results[integration.integration_name] = integration.patch!
  end
  results
end
```

## Tests to Create

### `test/braintrust/contrib_test.rb`

- Test `instrument!` with no arguments (all available)
- Test `instrument!(:openai)` (specific integration)
- Test `instrument!(only: [...])` filtering
- Test `instrument!(except: [...])` filtering
- Test return value hash
- Test idempotency

## Documentation

Update README with `instrument!` API examples.

## Dependencies

- [01-core-infrastructure.md](01-core-infrastructure.md) must be complete
- [02-openai-integration.md](02-openai-integration.md) must be complete (for testing)
