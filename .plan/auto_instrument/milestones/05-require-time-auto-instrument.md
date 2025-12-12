# Milestone 05: Require-time Auto-Instrument

## Goal

Enable instrumentation via `require` without explicit `init()` call, supporting Bundler and Rails workflows.

## What You Get

Works via Gemfile or Rails initializer without calling `init()`:

```ruby
# Gemfile - order doesn't matter!
gem "braintrust", require: "braintrust/contrib/auto_instrument"
gem "openai"
```

```ruby
# Or Rails initializer (config/initializers/braintrust.rb)
require "braintrust/contrib/auto_instrument"
```

Libraries loaded after the require are automatically instrumented.

## Success Criteria

- `require "braintrust/contrib/auto_instrument"` sets up instrumentation
- Works with Bundler (gem load order doesn't matter)
- Works with Rails (`after_initialize` hook)
- Works with plain Ruby scripts
- Idempotent setup (multiple requires are safe)
- Thread-safe with reentrancy guard

## Files to Create

### `lib/braintrust/contrib/auto_instrument.rb`

```ruby
# lib/braintrust/contrib/auto_instrument.rb
require "braintrust"

module Braintrust
  module Contrib
    module AutoInstrument
      class << self
        def setup!
          return if @setup_complete

          # Initialize Braintrust from environment variables
          # Silent failure if API key not set - spans just won't export
          Braintrust.init rescue nil

          # Patch integrations that are already loaded
          patch_available_integrations!

          # Set up deferred patching for libraries loaded later
          if rails_environment?
            setup_rails_hook!
          else
            setup_require_hook!
          end

          @setup_complete = true
        end

        def patch_available_integrations!
          Braintrust::Contrib.instrument!(
            only: parse_env_list("BRAINTRUST_INSTRUMENT_ONLY"),
            except: parse_env_list("BRAINTRUST_INSTRUMENT_EXCEPT")
          )
        end

        private

        def rails_environment?
          defined?(Rails) && Rails.respond_to?(:application) && Rails.application
        end

        def setup_rails_hook!
          # Rails after_initialize runs immediately if already initialized
          Rails.application.config.after_initialize do
            Braintrust::Contrib::AutoInstrument.patch_available_integrations!
          end
        end

        def setup_require_hook!
          original_require = Kernel.method(:require)
          registry = Registry.instance

          Kernel.define_method(:require) do |path|
            # Call original require first
            result = original_require.call(path)

            # Thread-local reentrancy guard
            unless Thread.current[:braintrust_in_require_hook]
              begin
                Thread.current[:braintrust_in_require_hook] = true

                # Filter and patch eligible integrations
                registry.integrations_for_require_path(path).each do |integration|
                  next unless integration.available? && integration.compatible?
                  integration.patch!
                end
              rescue => e
                Braintrust::Log.debug("Auto-instrument hook error: #{e.message}")
              ensure
                Thread.current[:braintrust_in_require_hook] = false
              end
            end

            result
          end
        end

        def parse_env_list(key)
          value = ENV[key]
          return nil unless value
          value.split(",").map(&:strip).map(&:to_sym)
        end
      end
    end
  end
end

# Auto-setup when required
Braintrust::Contrib::AutoInstrument.setup!
```

## Design Notes

### Why Require Hook?

The require hook catches libraries loaded after Braintrust, regardless of:
- Bundler gem ordering
- Dynamic requires
- Lazy loading

### Why Rails Hook?

For Rails, `after_initialize` is cleaner than the require hook because:
- All gems are already loaded
- No need to intercept requires
- Runs at a well-defined point in the boot process

### Thread Safety

| Component | Issue | Solution |
|-----------|-------|----------|
| Require hook | Reentrancy if patching triggers requires | Thread-local guard |
| Registry cache | Concurrent access | Double-checked locking (from Milestone 01) |
| Patcher | Concurrent patch calls | Mutex (from Milestone 01) |

### `init()` Relationship

- `auto_instrument.rb` calls `Braintrust.init` internally
- Provides true "zero-config" - just set `BRAINTRUST_API_KEY`
- If user calls `init()` explicitly, it's idempotent

## Tests to Create

### `test/braintrust/contrib/auto_instrument_test.rb`

- Test `setup!` patches available integrations
- Test `setup!` is idempotent
- Test require hook triggers patching
- Test reentrancy guard prevents infinite loops
- Test Rails hook (mock Rails environment)
- Test environment variable filtering

## Documentation

Update README:
- Add "Bundler Setup" section with Gemfile example
- Add "Rails Setup" section with initializer example
- Explain that gem order doesn't matter

## Dependencies

- [01-core-infrastructure.md](01-core-infrastructure.md) must be complete
- [02-openai-integration.md](02-openai-integration.md) must be complete
- [03-instrument-api.md](03-instrument-api.md) must be complete
- [04-init-auto-instrument.md](04-init-auto-instrument.md) must be complete
