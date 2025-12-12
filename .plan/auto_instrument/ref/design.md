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
- Total: ~40 lines per integration stub

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

### Explicit Registration Pattern

Integrations are registered explicitly in `lib/braintrust/contrib.rb` rather than auto-registering when loaded:

```ruby
# lib/braintrust/contrib.rb
require_relative "contrib/openai/integration"
Contrib::OpenAI::Integration.register!
```

**Rationale:**
- **No side effects**: Integration classes can be loaded without automatically registering them
- **Testability**: Tests can load integrations without polluting the global registry
- **Flexibility**: Tools (CI/CD, documentation generators, etc.) can inspect integrations without registration
- **Single source of truth**: `contrib.rb` shows exactly which integrations are registered

This differs from auto-registration (where `register!` is called at the end of the integration file) but provides better separation of concerns.

## Safety Considerations

1. **Fail-Safe Patching**: All patching wrapped in rescue blocks
2. **Idempotent**: Multiple calls to `patch!` are safe (no duplicate spans)
3. **No Breaking Changes**: Existing `.wrap()` API preserved for manual use
4. **Lazy Loading**: Integrations only load when target library is present
5. **Version Compatibility**: Check library versions before patching
6. **Graceful Degradation**: If patching fails, app continues without tracing

## Integration Filtering

### Why Two-Level Filtering?

As the number of integrations grows, efficient filtering becomes critical for performance:

**Performance Benefits:**
- **Faster startup**: Lightweight checks avoid loading unnecessary patcher code (~500 lines each)
- **Lower memory overhead**: Only load patchers for libraries actually in use
- **Minimal require-time cost**: Integration stubs are ~40 lines each, patchers load only when needed

**Without filtering:**
- When multiple integrations subscribe to the same require path, all their patchers would load
- Memory waste if wrong integration's patcher loads
- Slower require times as number of integrations grows
- Problem compounds with each ambiguous require path

**With two-level filtering:**
- Only eligible integration's patchers load
- O(1) checks before O(n) patcher loading
- Scales to dozens of integrations with minimal overhead

### Two-Level Filtering Strategy

**Level 1: Integration-Level (Lightweight, No Patcher Loading)**
- `available?`: Is the target library loaded? (~10 lines of code)
- `compatible?`: Is the library version compatible? (~20 lines of code)
- These checks happen BEFORE loading patcher code (~500 lines each)
- Only eligible integrations proceed to patching

**Level 2: Patcher-Level (After Patcher Loads)**
- `applicable?`: Should this specific patcher apply?
- Useful for version-specific patchers within one integration
- Checked under mutex lock before patching
- Can inspect loaded library structure (methods, constants, etc.)

### Example: OpenAI vs Ruby-OpenAI

Both gems use `require "openai"` but only one's code can be loaded:

```ruby
# When require "openai" happens:
# 1. Registry finds: [OpenAI::Integration, RubyOpenai::Integration]
# 2. Filter by available? (lightweight, no patcher loading):
#    - Check $LOADED_FEATURES to see which openai.rb was loaded
#    - OpenAI::Integration.available? → true if official gem
#    - RubyOpenai::Integration.available? → true if ruby-openai gem
# 3. Only one is available
# 4. Patch that one (NOW load its patcher - only the correct one)
```

**Result**: Only ~40 lines of integration stub code checked for the wrong gem, not ~500 lines of patcher code.

### Multiple Patchers Per Integration

An integration can have multiple patchers for different versions:

```ruby
class OpenAI::Integration
  def self.patcher_classes
    require_relative "patcher_v1"
    require_relative "patcher_v2"
    [Patcherv1, Patcherv2]
  end
end

class OpenAI::Patcherv1 < Patcher
  def self.applicable?
    # Check for v1.x API structure
    defined?(::OpenAI::Client) &&
      ::OpenAI::Client.instance_methods.include?(:chat)
  end
end
```

**Decision guide:**
- **Multiple integrations**: Different gems with same require path (avoids loading wrong patcher)
- **Multiple patchers**: Same gem, but incompatible API structures (all patchers load, one applies)

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
