# Braintrust Ruby SDK: Auto-Instrumentation Architecture Design

## Goal
Redesign the integration/instrumentation system to provide a simpler, "it just works" experience for users while maintaining safety and reusability.

## Key Requirements
1. **Simplicity**: Minimal configuration required; support for zero-code instrumentation
2. **Safety**: Fail gracefully; never break user applications
3. **Reusability**: Auto-instrumentation leverages manual instrumentation APIs

## Design Decisions (Confirmed)
- **Activation**: `init()` auto-instruments by default (opt-out via `auto_instrument: false`)
- **Patch Scope**: Class-level patching (all instances auto-traced)
- **Directory Structure**: Nested subdirectories per integration (plugin-style, severable)
- **Idempotency**: Multiple `init()` calls must not duplicate instrumentation

---

## Proposed User Experience

### Default: Zero-Config Auto-Instrument
```ruby
require "braintrust"
Braintrust.init  # Reads API key from env, auto-instruments all detected libraries

# All OpenAI/Anthropic/etc clients are automatically traced!
client = OpenAI::Client.new
response = client.chat.completions.create(...)  # Automatically traced
```

### Selective Instrumentation
```ruby
require "braintrust"
Braintrust.init(auto_instrument: [:openai, :anthropic])  # Only specific integrations
# OR
Braintrust.init(auto_instrument: {except: [:ruby_llm]})  # All except some
```

### Opt-Out of Auto-Instrumentation
```ruby
require "braintrust"
Braintrust.init(auto_instrument: false)  # Disable auto-instrumentation

# Manual wrapping still works
client = OpenAI::Client.new
Braintrust::Trace::OpenAI.wrap(client)
```

### Zero-Code (CLI Wrapper)
```bash
# Automatically instruments all supported libraries
braintrust exec -- ruby app.rb

# With options
braintrust exec --only openai,anthropic -- ruby app.rb
braintrust exec --except ruby_llm -- ruby app.rb
```

### Require-Time (for Bundler/Rails)
```ruby
# In Gemfile
gem "braintrust", require: "braintrust/contrib/auto_instrument"

# Or in config/initializers/braintrust.rb (Rails)
require "braintrust/contrib/auto_instrument"
```

### Manual (Current Behavior - Still Supported)
```ruby
require "braintrust"
Braintrust.init(auto_instrument: false)

client = OpenAI::Client.new
Braintrust::Trace::OpenAI.wrap(client)  # Explicit per-client wrapping (backwards compatible)
```

---

## Environment Variable Configuration

```bash
# Core settings (already exist)
BRAINTRUST_API_KEY=sk-...
BRAINTRUST_ORG_NAME=my-org
BRAINTRUST_DEFAULT_PROJECT=my-project

# Auto-instrumentation controls (new)
BRAINTRUST_INSTRUMENT_ONLY=openai,anthropic  # Comma-separated whitelist
BRAINTRUST_INSTRUMENT_EXCEPT=ruby_llm        # Comma-separated blacklist
```

---

## Architecture Design

### Directory Structure

```
lib/
├── braintrust.rb                 # Entry point - loads core + contrib (all-in-one)
│
└── braintrust/
    ├── contrib.rb                # Contrib entry point, loads registry + stubs
    ├── contrib/                  # 3rd party plugin framework (severable to own gem)
    │   ├── registry.rb           # Central integration registry
    │   ├── integration.rb        # Base integration module
    │   ├── patcher.rb            # Base patcher class
    │   ├── auto_instrument.rb    # Auto-instrumentation logic
    │   │
    │   ├── openai/               # Official OpenAI SDK (openai gem)
    │   │   ├── integration.rb    # Integration definition, registers itself
    │   │   └── patcher.rb        # Class-level patching for OpenAI::Client
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
    ├── trace/
    │   ├── span_processor.rb
    │   ├── span_filter.rb
    │   └── tokens.rb
    │
    └── ...                       # Other core files (state, config, api, eval)
```

### Key Design Principle: Severable Plugin Architecture

**Core has ZERO references to `contrib/`.** Contrib requires core, not vice versa.

This enables:
1. `contrib/` can be extracted to a separate gem (`braintrust-contrib`) in the future
2. Core SDK releases are independent of integration updates
3. Each integration folder is self-contained (can be extracted to its own gem)

**However**, `braintrust.rb` (the main entry point) *does* require `contrib.rb` for convenience - this is the "all-in-one" setup that most users want. The architectural boundary is between core files and contrib, not at the entry point.

**Namespace:** `Braintrust::Contrib` (not `Braintrust::Trace::Contrib`)

Each integration folder is a self-contained plugin that:
1. Registers itself with the central registry when loaded
2. Has no dependencies on other integrations
3. Can be extracted into a separate gem in the future
4. Leverages shared base classes for consistency

### Loading Strategy: Stub + Lazy Load

To minimize performance impact as the number of integrations grows:

**Eager loaded (always):**
- Integration "stubs" - tiny files with just metadata (name, gem_names, require_paths, version constraints)
- Base classes (Registry, Integration module, Patcher base)
- Total: ~50 lines per integration stub

**Lazy loaded (on first patch):**
- Patcher classes - heavy files with actual patching logic (~500 lines each)
- Only loaded for integrations that are actually instrumented

```ruby
# lib/braintrust/contrib.rb (eager loaded by braintrust.rb)
require_relative "contrib/registry"
require_relative "contrib/integration"
require_relative "contrib/patcher"

# Load integration stubs only (minimal metadata)
require_relative "contrib/openai/integration"
require_relative "contrib/anthropic/integration"
require_relative "contrib/ruby_openai/integration"
require_relative "contrib/ruby_llm/integration"
```

The lazy loading happens in the Integration's `patcher` method:
```ruby
def self.patcher
  require_relative "patcher"  # Heavy file loaded on-demand
  Patcher
end
```

### Base Integration Module

The Integration module is a "schema" - it defines metadata and delegates all patching logic to the Patcher class.

```ruby
# lib/braintrust/contrib/integration.rb
module Braintrust
  module Contrib
    # Mixin for integration classes
    # Include this in your integration and implement the required methods
    # Integration is a "schema" - metadata only; patching logic lives in Patcher
    module Integration
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Unique symbol name for this integration (e.g., :openai, :anthropic)
        def integration_name
          raise NotImplementedError, "#{self} must implement integration_name"
        end

        # Array of gem names this integration supports
        def gem_names
          raise NotImplementedError, "#{self} must implement gem_names"
        end

        # Require paths that correspond to this integration's target library
        # Used by auto-instrument to detect when library is loaded
        # Default: derived from gem_names
        def require_paths
          gem_names
        end

        # Is the target library loaded?
        def available?
          gem_names.any? { |name| Gem.loaded_specs.key?(name) }
        end

        # Minimum compatible version (optional, inclusive)
        def minimum_version
          nil
        end

        # Maximum compatible version (optional, inclusive)
        # Use when newer versions have breaking changes we don't yet support
        def maximum_version
          nil
        end

        # Is the library version compatible?
        def compatible?
          return false unless available?

          gem_names.each do |name|
            spec = Gem.loaded_specs[name]
            next unless spec

            version = spec.version
            if minimum_version && version < Gem::Version.new(minimum_version)
              return false
            end
            if maximum_version && version > Gem::Version.new(maximum_version)
              return false
            end
            return true
          end
          false
        end

        # Already patched? Delegates to patcher
        def patched?
          patcher.patched?
        end

        # Apply instrumentation (idempotent). Delegates to patcher
        # All thread-safety is handled by the Patcher base class
        def patch!(tracer_provider: nil)
          return false unless available? && compatible?
          patcher.patch!(tracer_provider)
        end

        # The patcher class (must inherit from Patcher base class)
        # Can be overridden to return version-specific patchers
        def patcher
          raise NotImplementedError, "#{self} must implement patcher"
        end

        # Register this integration with the global registry
        def register!
          Registry.instance.register(self)
        end
      end
    end
  end
end
```

### Base Patcher Class

```ruby
# lib/braintrust/contrib/patcher.rb
module Braintrust
  module Contrib
    # Context passed to perform_patch - extensible without breaking signatures
    PatchContext = Struct.new(:tracer_provider, keyword_init: true)

    # Base class for all patchers
    # Handles thread-safety and lifecycle; subclasses implement perform_patch
    class Patcher
      class << self
        def patched?
          @patched == true
        end

        def patch!(tracer_provider = nil)
          return true if patched?  # Fast path

          @patch_mutex ||= Mutex.new
          @patch_mutex.synchronize do
            return true if patched?  # Double-check under lock

            context = PatchContext.new(
              tracer_provider: tracer_provider || ::OpenTelemetry.tracer_provider
            )

            perform_patch(context)
            @patched = true
          end
          Log.debug("Patched #{name}")
          true
        rescue => e
          Log.error("Failed to patch #{name}: #{e.message}")
          false
        end

        # Subclasses implement this - receives PatchContext
        def perform_patch(context)
          raise NotImplementedError, "#{self} must implement perform_patch"
        end
      end
    end
  end
end
```

### Registry

Thread-safe singleton with double-checked locking for the require path cache.

```ruby
# lib/braintrust/contrib/registry.rb
require "singleton"

module Braintrust
  module Contrib
    class Registry
      include Singleton

      def initialize
        @integrations = {}
        @require_path_map = nil  # Lazy cache: { "openai" => [Integration], ... }
        @mutex = Mutex.new
      end

      def register(integration_class)
        @mutex.synchronize do
          @integrations[integration_class.integration_name] = integration_class
          @require_path_map = nil  # Invalidate cache
        end
      end

      def [](name)
        @integrations[name.to_sym]
      end

      def available
        @integrations.values.select(&:available?)
      end

      def each(&block)
        @integrations.values.each(&block)
      end

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

      # Returns integrations associated with this require path
      # Thread-safe with double-checked locking for performance
      def integrations_for_require_path(path)
        # Fast path: cache already built (no lock needed for read)
        map = @require_path_map
        if map.nil?
          # Slow path: build cache under lock
          map = @mutex.synchronize do
            # Double-check: another thread may have built it while we waited
            @require_path_map ||= build_require_path_map
          end
        end
        basename = File.basename(path.to_s, ".rb")
        # Use fetch with frozen empty array to avoid mutating shared cache
        map.fetch(basename, EMPTY_ARRAY)
      end

      private

      EMPTY_ARRAY = [].freeze

      def build_require_path_map
        # Called under @mutex lock
        # Build a regular hash (no default proc) to avoid mutation on read
        map = {}
        @integrations.each_value do |integration|
          integration.require_paths.each do |req|
            map[req] ||= []
            map[req] << integration
          end
        end
        # Freeze arrays to prevent accidental mutation
        map.each_value(&:freeze)
        map.freeze
      end
    end
  end
end
```

### Concrete Example: OpenAI Integration

```ruby
# lib/braintrust/contrib/openai/integration.rb
# STUB FILE - minimal metadata, eager loaded
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
          ["openai"]  # For auto-instrument require hook detection
        end

        def self.minimum_version
          "0.1.0"
        end

        # def self.maximum_version
        #   "2.0.0"  # Uncomment if newer versions break compatibility
        # end

        # Lazy-load the patcher only when actually patching
        def self.patcher
          require_relative "patcher"
          Patcher
        end
      end
    end
  end
end

# Auto-register when this file is loaded
Braintrust::Contrib::OpenAI::Integration.register!
```

```ruby
# lib/braintrust/contrib/openai/patcher.rb
# HEAVY FILE - lazy loaded on first patch! call
require_relative "../patcher"

module Braintrust
  module Contrib
    module OpenAI
      class Patcher < Braintrust::Contrib::Patcher
        class << self
          # Implements the patching logic - called by base class with PatchContext
          def perform_patch(context)
            tracer_provider = context.tracer_provider
            # Patch the Client class so all instances are auto-traced
            patch_chat_completions(tracer_provider)
            patch_responses(tracer_provider) if responses_available?
          end

          private

          def patch_chat_completions(tracer_provider)
            # Create wrapper module (similar to existing wrap logic)
            wrapper = create_chat_completions_wrapper(tracer_provider)

            # Patch at class level - affects all future instances
            ::OpenAI::Client.prepend(Module.new do
              define_method(:chat) do
                chat_resource = super()
                unless chat_resource.singleton_class.ancestors.include?(wrapper)
                  chat_resource.completions.singleton_class.prepend(wrapper)
                end
                chat_resource
              end
            end)
          end

          def create_chat_completions_wrapper(tracer_provider)
            # ... wrapper module with create, stream, stream_raw methods
            # (refactored from existing openai.rb code)
          end

          def responses_available?
            # Check if the OpenAI gem version supports responses API
            defined?(::OpenAI::Client) && ::OpenAI::Client.instance_methods.include?(:responses)
          end
        end
      end
    end
  end
end
```

### Auto-Instrument Entry Point

Uses a require hook with thread-local reentrancy guard to safely patch integrations when their libraries are loaded.

**Design Note:** `auto_instrument.rb` calls `Braintrust.init` internally to ensure tracing is configured. This provides true "zero-config" behavior - users don't need to call `init()` separately when using auto-instrument. The `init()` call reads API key and other settings from environment variables.

```ruby
# lib/braintrust/contrib/auto_instrument.rb
require "braintrust"

# Auto-instrument is designed to be required early (e.g., via RUBYOPT or Gemfile)
# It defers actual patching until libraries are loaded using a Kernel.require hook

module Braintrust
  module Contrib
    module AutoInstrument
      class << self
        def setup!
          return if @setup_complete

          # Initialize Braintrust from environment variables
          # This sets up tracing infrastructure so spans are actually exported
          Braintrust.init rescue nil  # Silently fail if API key not set

          # Always: patch what's available right now
          patch_available_integrations!

          # Select deferred patching strategy
          if rails_environment?
            setup_rails_hook!
          else
            # Default: always use require hook for safety
            # Handles Bundler, plain Ruby, CLI exec - any case where
            # gems might be required after braintrust
            setup_require_hook!
          end

          @setup_complete = true
        end

        def patch_available_integrations!
          Registry.instance.instrument!(
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
          # (via ActiveSupport.on_load behavior)
          Rails.application.config.after_initialize do
            Braintrust::Contrib::AutoInstrument.patch_available_integrations!
          end
        end

        def setup_require_hook!
          original_require = Kernel.method(:require)
          registry = Registry.instance

          Kernel.define_method(:require) do |path|
            # Call original require first - if it raises, the error propagates
            # naturally without any interference from our instrumentation code
            result = original_require.call(path)

            # Thread-local reentrancy guard prevents infinite recursion
            # if patching triggers additional requires
            unless Thread.current[:braintrust_in_require_hook]
              begin
                Thread.current[:braintrust_in_require_hook] = true
                # Fast path: hash lookup returns only integrations matching this path
                registry.integrations_for_require_path(path).each do |integration|
                  integration.patch!
                end
              rescue => e
                # Only catch errors from our patching code, not from require
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

### CLI Wrapper

```ruby
#!/usr/bin/env ruby
# bin/braintrust

require "optparse"

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: braintrust exec [options] -- COMMAND"

  opts.on("--only INTEGRATIONS", "Only instrument these (comma-separated)") do |v|
    options[:only] = v
  end

  opts.on("--except INTEGRATIONS", "Skip these integrations (comma-separated)") do |v|
    options[:except] = v
  end
end.parse!

# Set environment variables for auto_instrument
ENV["BRAINTRUST_INSTRUMENT_ONLY"] = options[:only] if options[:only]
ENV["BRAINTRUST_INSTRUMENT_EXCEPT"] = options[:except] if options[:except]

# Inject auto-instrument via RUBYOPT
rubyopt = ENV["RUBYOPT"] || ""
ENV["RUBYOPT"] = "#{rubyopt} -rbraintrust/contrib/auto_instrument"

# Execute the command
exec(*ARGV)
```


---

## Safety Considerations

1. **Fail-Safe Patching**: All patching wrapped in rescue blocks
2. **Idempotent**: Multiple calls to `patch!` are safe (no duplicate spans)
3. **No Breaking Changes**: Existing `.wrap()` API preserved for manual use
4. **Lazy Loading**: Integrations only load when target library is present
5. **Version Compatibility**: Check library versions before patching
6. **Graceful Degradation**: If patching fails, app continues without tracing

---

## Design Considerations

### `init()` vs `auto_instrument` Relationship
- `auto_instrument.rb` calls `Braintrust.init` internally (silent failure if no API key)
- This provides true "zero-config" - just `require "braintrust/auto_instrument"` and set `BRAINTRUST_API_KEY`
- If user also calls `init()` explicitly, it's idempotent (State is replaced, tracing reconfigured)
- Patching is independent of `init()` - works even if `init()` fails (spans just won't export)

### Existing Clients Not Patched
Class-level patching only affects clients created *after* patching occurs. Clients instantiated before `patch!` is called will not be instrumented. This is documented as expected behavior - initialize Braintrust early in your application lifecycle.

### Idempotency
- Multiple calls to `init()` are safe (replaces global state)
- Multiple calls to `patch!` are safe (returns `true` immediately if already patched)
- Multiple calls to `auto_instrument.setup!` are safe (returns immediately if complete)

---

## Thread Safety Summary

All thread safety decisions from stability analysis:

| Component | Issue | Solution |
|-----------|-------|----------|
| Registry cache | Race condition reading `@require_path_map` | Double-checked locking pattern |
| Patcher `patch!` | Race condition setting `@patched` | Mutex in Patcher base class with double-check |
| Require hook | Reentrancy if patching triggers requires | Thread-local guard (`Thread.current[:braintrust_in_require_hook]`) |
| Rails hook | Already initialized scenario | Not an issue - `after_initialize` runs immediately via ActiveSupport.on_load |
| `require_relative` | Not hooked by Kernel.require | Not an issue - require_relative resolves before braintrust loads |

---

## Backwards Compatibility

The existing manual wrapping API will continue to work:
```ruby
client = OpenAI::Client.new
Braintrust::Trace::OpenAI.wrap(client)  # Still works!
```

The `Braintrust::Trace::OpenAI` module (at `lib/braintrust/trace/contrib/openai.rb`) becomes a compatibility shim that:
1. Checks if class-level patching already applied (no double-wrap)
2. Delegates to the same patcher code used by auto-instrument (`Braintrust::Contrib::OpenAI::Patcher`)

---

## Implementation Phases

Phases are ordered from most manual to most "magic". Each phase builds on the previous.
We can stop at any phase if the next becomes impractical - that's "good enough".

---

### Phase 1: Core Infrastructure + OpenAI Integration

**Goal**: Get the framework working end-to-end with one integration as proof of concept.

**Success Criteria**: `Braintrust::Contrib::OpenAI::Integration.patch!` works and traces all OpenAI client instances.

**Files to create:**

#### `lib/braintrust/contrib.rb`
Entry point that loads the contrib framework:
- Requires registry, integration, patcher base classes
- Requires all integration stubs (eager load minimal metadata)

#### `lib/braintrust/contrib/registry.rb`
Central registry for managing integrations. Thread-safe singleton that tracks:
- All registered integrations by name
- Which integrations are available (target library loaded)
- Which integrations have been patched
- Provides `instrument!` method for batch patching

#### `lib/braintrust/contrib/integration.rb`
Base module that defines the integration contract:
- `integration_name` - unique symbol identifier (e.g., `:openai`)
- `gem_names` - array of gem names this integration supports
- `available?` - is the target library loaded?
- `compatible?` - version check against `minimum_version`
- `patched?` - has this already been patched? (idempotency)
- `patch!(tracer_provider:)` - apply instrumentation
- `patcher` - returns the Patcher class
- `register!` - register this integration with the global registry

#### `lib/braintrust/contrib/patcher.rb`
Base class for all patchers:
- Thread-safe `patch!` with double-checked locking
- `patched?` to check if already patched
- `PatchContext` struct for extensible parameters
- Subclasses implement `perform_patch(context)`

#### `lib/braintrust/contrib/openai/integration.rb`
Stub file with minimal metadata (eager loaded):
```ruby
module Braintrust::Contrib::OpenAI
  class Integration
    include Braintrust::Contrib::Integration

    def self.integration_name = :openai
    def self.gem_names = ["openai"]
    def self.minimum_version = "0.1.0"
    # def self.maximum_version = "2.0.0"  # If needed

    def self.patcher
      require_relative "patcher"  # Lazy load heavy file
      Patcher
    end
  end
end

Braintrust::Contrib::OpenAI::Integration.register!
```

#### `lib/braintrust/contrib/openai/patcher.rb`
Refactored from existing `trace/contrib/openai.rb`:
- Inherits from `Braintrust::Contrib::Patcher` base class
- Implements `perform_patch(context)` - receives `PatchContext` with tracer_provider
- `patch_chat_completions` - wrapper for chat.completions
- `patch_responses` - wrapper for responses API (if available)
- Reuses existing span creation, aggregation, metrics logic from current code
- Key difference: patches at **class level** not instance level

**Files to modify:**

#### `lib/braintrust.rb`
- Add `require_relative "braintrust/contrib"` to load contrib framework

#### `lib/braintrust/trace.rb`
- Remove all `require_relative "trace/contrib/..."` lines (severing the dependency)

#### `lib/braintrust/trace/contrib/openai.rb` (existing)
- Keep as compatibility shim for existing `.wrap(client)` API
- Delegates to `Braintrust::Contrib::OpenAI::Patcher` internally

**Tests to create/update:**
- `test/braintrust/contrib/registry_test.rb`
- `test/braintrust/contrib/integration_test.rb`
- `test/braintrust/trace/openai_test.rb` - verify existing tests still pass
- Add tests for class-level patching (new behavior)
- Add tests for idempotency (calling patch! twice doesn't double-wrap)

**Usage after this phase:**
```ruby
require "braintrust"
Braintrust.init

# Explicitly patch OpenAI
Braintrust::Contrib::OpenAI::Integration.patch!

# All clients now auto-traced
client = OpenAI::Client.new
client.chat.completions.create(...)  # Traced!
```

---

### Phase 2: Explicit `instrument!` API

**Goal**: Add a cleaner public API for instrumenting integrations.

**Success Criteria**: `Braintrust::Contrib.instrument!(:openai)` works.

**Files to modify:**

#### `lib/braintrust/contrib.rb`
- Add `Braintrust::Contrib.instrument!(*integrations)` convenience method
- Add `Braintrust::Contrib.registry` accessor

**Usage after this phase:**
```ruby
require "braintrust"
Braintrust.init
Braintrust::Contrib.instrument!(:openai)  # Cleaner API

client = OpenAI::Client.new
client.chat.completions.create(...)  # Traced!
```

---

### Phase 3: `init(auto_instrument: true)` Integration

**Goal**: Integrate auto-instrumentation into the `init()` call.

**Success Criteria**: `Braintrust.init` auto-instruments all available integrations by default.

**Files to modify:**

#### `lib/braintrust.rb` (or `lib/braintrust/braintrust.rb`)
- Add `auto_instrument` parameter to `init()`
- Default to `true` (opt-out)
- Support selective instrumentation: `auto_instrument: [:openai]` or `{except: [:ruby_llm]}`

**Usage after this phase:**
```ruby
require "braintrust"
Braintrust.init  # Auto-instruments all available integrations

client = OpenAI::Client.new
client.chat.completions.create(...)  # Traced!
```

```ruby
# Opt-out
Braintrust.init(auto_instrument: false)
```

---

### Phase 4: Require-time Auto-Instrument

**Goal**: Enable instrumentation via `require` without explicit `init()` call.

**Success Criteria**: `require "braintrust/contrib/auto_instrument"` in Gemfile/initializer works.

**Strategy**: Blended approach - always set up require hook unless we have something better (Rails).

**Design Principles:**
- Integration and Registry have no knowledge of auto-instrumentation
- They provide generic primitives (`require_paths`, `integrations_for_require_path`) that AutoInstrument consumes
- Thread-local reentrancy guard prevents infinite recursion if patching triggers requires
- Rails uses `after_initialize` hook which runs immediately if already initialized

**Files to create:**

#### `lib/braintrust/contrib/auto_instrument.rb`
See "Auto-Instrument Entry Point" section above for full implementation.

**Strategy Summary:**

| Environment | Detection | Deferred Patching Strategy |
|-------------|-----------|---------------------------|
| Rails | `defined?(Rails) && Rails.application` | `after_initialize` hook (cleaner) |
| Everything else | Default | `Kernel.require` hook (safe default) |

**Why always use require hook (except Rails)?**
- Gemfile order ≠ require order (Bundler resolves dependencies)
- Plain Ruby scripts might do dynamic requires
- Require hook overhead is minimal (one hash lookup per require)
- "It just works" is more important than micro-optimization

**Why no TracePoint?**
- TracePoint(:class) fires on every class definition - too slow
- Require hook is much faster and sufficient for our needs

**Safety Features:**
- Thread-local reentrancy guard (`Thread.current[:braintrust_in_require_hook]`)
- Double-checked locking in Registry for thread-safe cache access
- Mutex-protected patching in Patcher base class
- All errors caught and logged, never propagated to break user code

**Usage after this phase:**
```ruby
# Gemfile - order doesn't matter anymore!
gem "braintrust", require: "braintrust/contrib/auto_instrument"
gem "openai"

# Or Rails initializer
require "braintrust/contrib/auto_instrument"
```

---

### Phase 5: CLI Wrapper

**Goal**: Zero-code instrumentation via command line.

**Success Criteria**: `braintrust exec -- ruby app.rb` instruments the app without code changes.

**Challenges**:
- Need to inject require before app loads
- Cross-platform considerations
- May conflict with other RUBYOPT settings

**Files to create:**

#### `bin/braintrust` (or `exe/braintrust`)
```bash
braintrust exec -- ruby app.rb
braintrust exec --only openai -- bundle exec rails s
```

Implementation:
- Parse options (`--only`, `--except`)
- Set environment variables
- Inject `-rbraintrust/auto_instrument` via `RUBYOPT`
- `exec` the provided command

**Files to modify:**
- `braintrust.gemspec` - Add bin executable

**Stop here if**: RUBYOPT injection proves unreliable across environments.

---

### Phase 6: Remaining Integrations

**Goal**: Port all existing integrations to the new framework.

**Integrations to port:**

**Anthropic** (`lib/braintrust/contrib/anthropic/`)
- Patches `Anthropic::Client` at class level
- Wraps `messages.create` and `messages.stream`

**Ruby-OpenAI** (`lib/braintrust/contrib/ruby_openai/`)
- Different gem, same `OpenAI` namespace (collision handling)
- Patches alexrudall's ruby-openai gem

**RubyLLM** (`lib/braintrust/contrib/ruby_llm/`)
- Already supports class-level patching
- Refactor into new structure

**Note:** The old files at `lib/braintrust/trace/contrib/` become compatibility shims that delegate to the new `Braintrust::Contrib::*` modules.

---

### Phase 7: Documentation

- Update README with new "Getting Started" section
- Add UPGRADING.md for migration from `.wrap()` to auto-instrument
- Update/add examples for each setup pattern

---

## Current Phase Files Summary (Phase 1)

### Files to Create (6)
```
lib/braintrust/contrib.rb                     # Entry point, eager loads stubs
lib/braintrust/contrib/registry.rb            # Thread-safe singleton with double-checked locking
lib/braintrust/contrib/integration.rb         # Base module (schema only, delegates to patcher)
lib/braintrust/contrib/patcher.rb             # Base class with thread-safe patch! and PatchContext
lib/braintrust/contrib/openai/integration.rb  # Stub (eager loaded)
lib/braintrust/contrib/openai/patcher.rb      # Heavy patching logic (lazy loaded)
```

### Files to Modify (3)
```
lib/braintrust.rb                      # Add require_relative "braintrust/contrib"
lib/braintrust/trace.rb                # Remove require_relative "trace/contrib/..." lines
lib/braintrust/trace/contrib/openai.rb # Compatibility shim (keep .wrap() working)
```

### Tests to Create (2)
```
test/braintrust/contrib/registry_test.rb
test/braintrust/contrib/integration_test.rb
```

---

## Future Improvements

Features intentionally deferred to keep initial implementation simple:

### Core-Only Require
Add `lib/braintrust/core.rb` for users who want minimal footprint without contrib overhead:

```ruby
require "braintrust/core"  # Just core (State, Config, Trace, API, Eval)
# No integrations loaded - smaller memory footprint
```

This would be useful for:
- Applications that don't use any supported LLM libraries
- Custom instrumentation scenarios
- Reducing startup time in environments where contrib isn't needed

When implemented, `braintrust.rb` would become:
```ruby
require_relative "braintrust/core"
require_relative "braintrust/contrib"
```

### Per-Integration Configuration
Add a `Configuration` class hierarchy for integration-specific settings.

Configuration values could be derived from multiple sources (in priority order):
1. Programmatic configuration via `configure` block
2. Environment variables (e.g., `BRAINTRUST_OPENAI_INCLUDE_PROMPTS=false`)
3. Configuration file (e.g., `.braintrust.yml` or `braintrust.rb` initializer)

```ruby
# lib/braintrust/contrib/configuration.rb
class Configuration
  attr_accessor :enabled  # default: true
end

# lib/braintrust/contrib/openai/configuration.rb
class Configuration < Braintrust::Contrib::Configuration
  attr_accessor :trace_chat_completions  # default: true
  attr_accessor :trace_responses         # default: true
  attr_accessor :include_prompts         # default: true (for privacy control)
end
```

Usage:
```ruby
Braintrust::Contrib::OpenAI::Integration.configure do |config|
  config.include_prompts = false  # Don't log prompts for privacy
end
```

### Span Filtering by Integration
Allow filtering spans based on integration type or other criteria.

### Metrics Collection
Aggregate metrics across integrations (total tokens, latency percentiles, etc.).
