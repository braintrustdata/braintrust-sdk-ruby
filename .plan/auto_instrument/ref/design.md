# Technical Design: Auto-Instrumentation

This document covers the technical architecture and implementation strategy for auto-instrumentation.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       braintrust.rb                         │
│                     (main entry point)                      │
└────────────────────────────┬────────────────────────────────┘
                             │ requires
            ┌────────────────┴────────────────┐
            ▼                                 ▼
┌────────────────────┐              ┌────────────────────────┐
│     Core SDK       │              │   Contrib Framework    │
│  (trace, state,    │              │  (registry, base       │
│   config, api)     │              │   classes, auto-       │
│                    │              │   instrument)          │
│  NO contrib refs   │◄─────────────│                        │
└────────────────────┘   uses core  └───────────┬────────────┘
                                                │ loads
                 ┌──────────┬───────────┬───────┴───────┬──────────┐
                 ▼          ▼           ▼               ▼          ▼
           ┌─────────┐ ┌──────────┐ ┌─────────┐ ┌──────────┐ ┌─────────┐
           │ OpenAI  │ │Anthropic │ │  Ruby-  │ │ RubyLLM  │ │   ...   │
           │         │ │          │ │ OpenAI  │ │          │ │         │
           └─────────┘ └──────────┘ └─────────┘ └──────────┘ └─────────┘
                    (each integration is a self-contained plugin)
```

## Design Principles

- **Severable**: Contrib framework can be extracted to a separate gem; integrations are independent plugins
- **Lazy loading**: Heavy patcher code only loads when the integration is actually used
- **Fail-safe**: All patching wrapped in rescue blocks; errors logged, never raised
- **Idempotent**: Multiple `init()` or `patch!` calls are safe (no duplicate instrumentation)

## Directory Structure

```
lib/
├── braintrust.rb                 # Entry point - loads core + contrib
│
└── braintrust/
    ├── contrib.rb                # Contrib entry point, loads registry + stubs
    ├── contrib/
    │   ├── registry.rb           # Central integration registry
    │   ├── integration.rb        # Base integration module
    │   ├── patcher.rb            # Base patcher class
    │   ├── auto_instrument.rb    # Auto-instrumentation logic
    │   │
    │   ├── openai/               # Official OpenAI SDK
    │   │   ├── integration.rb    # Integration definition
    │   │   └── patcher.rb        # Class-level patching
    │   │
    │   ├── anthropic/
    │   │   ├── integration.rb
    │   │   └── patcher.rb
    │   │
    │   ├── ruby_openai/          # alexrudall/ruby-openai gem
    │   │   ├── integration.rb
    │   │   └── patcher.rb
    │   │
    │   └── ruby_llm/
    │       ├── integration.rb
    │       └── patcher.rb
    │
    ├── trace.rb                  # Core tracing (NO contrib references)
    └── ...                       # Other core files
```

### Key Principle: Severable Plugin Architecture

**Core has ZERO references to `contrib/`.** Contrib requires core, not vice versa.

This enables:
1. `contrib/` can be extracted to a separate gem (`braintrust-contrib`) in the future
2. Core SDK releases are independent of integration updates
3. Each integration folder is self-contained (can be extracted to its own gem)

Each integration folder is a self-contained plugin that:
1. Registers itself with the central registry when loaded
2. Has no dependencies on other integrations
3. Can be extracted into a separate gem in the future
4. Leverages shared base classes for consistency

## Loading Strategy: Stub + Lazy Load

To minimize performance impact as the number of integrations grows:

**Eager loaded (always):**
- Integration "stubs" - tiny files with just metadata (name, gem_names, require_paths, version constraints)
- Base classes (Registry, Integration module, Patcher base)
- Total: ~50 lines per integration stub

**Lazy loaded (on first patch):**
- Patcher classes - heavy files with actual patching logic (~500 lines each)
- Only loaded for integrations that are actually instrumented

```ruby
# The lazy loading happens in the Integration's patcher method:
def self.patcher
  require_relative "patcher"  # Heavy file loaded on-demand
  Patcher
end
```

## Safety Considerations

1. **Fail-Safe Patching**: All patching wrapped in rescue blocks
2. **Idempotent**: Multiple calls to `patch!` are safe (no duplicate spans)
3. **No Breaking Changes**: Existing `.wrap()` API preserved for manual use
4. **Lazy Loading**: Integrations only load when target library is present
5. **Version Compatibility**: Check library versions before patching
6. **Graceful Degradation**: If patching fails, app continues without tracing

## Thread Safety

| Component | Issue | Solution |
|-----------|-------|----------|
| Registry cache | Race condition reading `@require_path_map` | Double-checked locking pattern |
| Patcher `patch!` | Race condition setting `@patched` | Mutex in Patcher base class with double-check |
| Require hook | Reentrancy if patching triggers requires | Thread-local guard (`Thread.current[:braintrust_in_require_hook]`) |
| Rails hook | Already initialized scenario | Not an issue - `after_initialize` runs immediately via ActiveSupport.on_load |

## Backwards Compatibility

The existing manual wrapping API will continue to work:
```ruby
client = OpenAI::Client.new
Braintrust::Trace::OpenAI.wrap(client)  # Still works!
```

The `Braintrust::Trace::OpenAI` module becomes a compatibility shim that:
1. Checks if class-level patching already applied (no double-wrap)
2. Delegates to the same patcher code used by auto-instrument

## Known Limitations

### Existing Clients Not Patched

Class-level patching only affects clients created *after* patching occurs. Clients instantiated before `patch!` is called will not be instrumented. This is documented as expected behavior - initialize Braintrust early in your application lifecycle.

### Require Hook Scope

The `Kernel.require` hook only intercepts `require` calls, not `require_relative`. This is acceptable because:
- Third-party gems use `require` to load their entry points
- `require_relative` is typically used for internal files within a gem

## Environment Variables

```bash
# Auto-instrumentation controls
BRAINTRUST_INSTRUMENT_ONLY=openai,anthropic  # Comma-separated whitelist
BRAINTRUST_INSTRUMENT_EXCEPT=ruby_llm        # Comma-separated blacklist
```

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Patching breaks target library | Low | High | Version constraints, comprehensive tests |
| Performance overhead at require-time | Low | Medium | Stub + lazy load pattern |
| Thread safety issues | Low | High | Double-checked locking, thread-local guards |
| RUBYOPT conflicts (CLI) | Medium | Low | Append to existing RUBYOPT, don't replace |
| Namespace collisions (ruby-openai vs openai) | Medium | Medium | Explicit gem detection via `Gem.loaded_specs` |
