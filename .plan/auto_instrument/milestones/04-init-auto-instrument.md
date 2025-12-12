# Milestone 04: Init Auto-Instrument

## Goal

Integrate auto-instrumentation into the `init()` call, enabled by default.

## What You Get

`Braintrust.init` auto-instruments all available integrations (zero-config):

```ruby
require "braintrust"
Braintrust.init  # Auto-instruments everything!

client = OpenAI::Client.new
client.chat.completions.create(...)  # Traced!
```

With opt-out and selective options:

```ruby
# Opt-out completely
Braintrust.init(auto_instrument: false)

# Only specific integrations
Braintrust.init(auto_instrument: { only: [:openai, :anthropic] })

# All except some
Braintrust.init(auto_instrument: { except: [:ruby_llm] })
```

## Success Criteria

- `Braintrust.init` auto-instruments by default
- `auto_instrument: false` disables auto-instrumentation
- `auto_instrument: { only: [...] }` enables only specified integrations
- `auto_instrument: { except: [...] }` excludes specified integrations
- Multiple `init()` calls don't duplicate instrumentation (idempotent)
- Environment variable `BRAINTRUST_AUTO_INSTRUMENT` enables/disables auto-instrumentation
- Environment variables `BRAINTRUST_INSTRUMENT_ONLY` and `BRAINTRUST_INSTRUMENT_EXCEPT` work

## Files to Modify

### `lib/braintrust.rb` (or `lib/braintrust/braintrust.rb`)

Add `auto_instrument` parameter to `init()`:

```ruby
module Braintrust
  class << self
    # @param auto_instrument [Boolean, Hash, nil] Auto-instrumentation config
    #   - nil (default): use BRAINTRUST_AUTO_INSTRUMENT env var, or enable if not set
    #   - true: explicitly enable (overrides BRAINTRUST_AUTO_INSTRUMENT=false)
    #   - false: explicitly disable (overrides BRAINTRUST_AUTO_INSTRUMENT=true)
    #   - Hash with :only or :except keys for filtering
    def init(
      api_key: nil,
      org_name: nil,
      project: nil,
      auto_instrument: nil,
      **options
    )
      # ... existing init logic ...

      # Auto-instrument based on parameter
      perform_auto_instrument(auto_instrument)

      # ... rest of init ...
    end

    private

    def perform_auto_instrument(config)
      # Determine if auto-instrumentation should run
      should_instrument = case config
      when nil
        # Not explicitly configured - check env var (default to true)
        ENV["BRAINTRUST_AUTO_INSTRUMENT"] != "false"
      when false
        # Explicitly disabled in code
        false
      when true, Hash
        # Explicitly enabled in code
        true
      end

      return unless should_instrument

      # Parse filter environment variable overrides
      only = parse_env_list("BRAINTRUST_INSTRUMENT_ONLY")
      except = parse_env_list("BRAINTRUST_INSTRUMENT_EXCEPT")

      # Apply configuration
      if config.is_a?(Hash)
        only = config[:only] || only
        except = config[:except] || except
      end

      Braintrust::Contrib.instrument!(only: only, except: except)
    end

    def parse_env_list(key)
      value = ENV[key]
      return nil unless value
      value.split(",").map(&:strip).map(&:to_sym)
    end
  end
end
```

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `BRAINTRUST_AUTO_INSTRUMENT` | Enable/disable auto-instrumentation (only used if not explicitly configured in code) | `false` |
| `BRAINTRUST_INSTRUMENT_ONLY` | Comma-separated whitelist | `openai,anthropic` |
| `BRAINTRUST_INSTRUMENT_EXCEPT` | Comma-separated blacklist | `ruby_llm` |

**Precedence rules:**
- Explicit code configuration always takes precedence over `BRAINTRUST_AUTO_INSTRUMENT`
- Programmatic filter options (`only`/`except`) override environment variables:
  - If `only` specified in code, it overrides `BRAINTRUST_INSTRUMENT_ONLY`
  - If `except` specified in code, it overrides `BRAINTRUST_INSTRUMENT_EXCEPT`
  - Environment variables only apply when not specified in code

## Tests to Create

### `test/braintrust/init_auto_instrument_test.rb`

- Test `init()` auto-instruments by default (when `BRAINTRUST_AUTO_INSTRUMENT` not set)
- Test `init()` respects `BRAINTRUST_AUTO_INSTRUMENT=false` (skips instrumentation)
- Test `init()` ignores `BRAINTRUST_AUTO_INSTRUMENT=true` (already default behavior)
- Test `init(auto_instrument: false)` skips instrumentation even if `BRAINTRUST_AUTO_INSTRUMENT=true`
- Test `init(auto_instrument: true)` instruments even if `BRAINTRUST_AUTO_INSTRUMENT=false`
- Test `init(auto_instrument: { only: [:openai] })` instruments even if `BRAINTRUST_AUTO_INSTRUMENT=false`
- Test `init(auto_instrument: { only: [:openai] })` only instruments specified
- Test `init(auto_instrument: { except: [:ruby_llm] })` excludes specified
- Test idempotency (multiple init calls)
- Test environment variable `BRAINTRUST_INSTRUMENT_ONLY`
- Test environment variable `BRAINTRUST_INSTRUMENT_EXCEPT`
- Test env + programmatic combination

## Documentation

Update README:
- Update "Getting Started" to show zero-config usage
- Add section on `auto_instrument` parameter options
- Document environment variables

## Dependencies

- [01-core-infrastructure.md](01-core-infrastructure.md) must be complete
- [02-openai-integration.md](02-openai-integration.md) must be complete
- [03-instrument-api.md](03-instrument-api.md) must be complete
