# Milestone 01: Core Infrastructure

## Goal

Establish the contrib framework foundation that provides a consistent interface for all integrations.

## What You Get

- Consistent interface across integrations
- Scales to many libraries without code duplication
- Enables reliable auto-instrumentation in later milestones

## Success Criteria

- `Braintrust::Contrib::Registry` can register and look up integrations
- `Braintrust::Contrib::Integration` module defines the integration contract
- `Braintrust::Contrib::Patcher` base class handles thread-safe patching
- All base classes have tests

## Files to Create

### `lib/braintrust/contrib.rb`

Entry point that loads the contrib framework:

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
    end
  end
end

# Load integration stubs (eager load minimal metadata)
# These will be added in subsequent milestones
```

### `lib/braintrust/contrib/registry.rb`

Thread-safe singleton registry with double-checked locking:

```ruby
# lib/braintrust/contrib/registry.rb
require "singleton"

module Braintrust
  module Contrib
    class Registry
      include Singleton

      def initialize
        @integrations = {}
        @require_path_map = nil  # Lazy cache
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

      def all
        @integrations.values
      end

      def available
        @integrations.values.select(&:available?)
      end

      def each(&block)
        @integrations.values.each(&block)
      end

      # Returns integrations associated with this require path
      # Thread-safe with double-checked locking for performance
      def integrations_for_require_path(path)
        map = @require_path_map
        if map.nil?
          map = @mutex.synchronize do
            @require_path_map ||= build_require_path_map
          end
        end
        basename = File.basename(path.to_s, ".rb")
        map.fetch(basename, EMPTY_ARRAY)
      end

      private

      EMPTY_ARRAY = [].freeze

      def build_require_path_map
        map = {}
        @integrations.each_value do |integration|
          integration.require_paths.each do |req|
            map[req] ||= []
            map[req] << integration
          end
        end
        map.each_value(&:freeze)
        map.freeze
      end
    end
  end
end
```

### `lib/braintrust/contrib/integration.rb`

Base module defining the integration contract (schema only, delegates to patcher):

```ruby
# lib/braintrust/contrib/integration.rb
module Braintrust
  module Contrib
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

        # Require paths for auto-instrument detection (default: gem_names)
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
            return false if minimum_version && version < Gem::Version.new(minimum_version)
            return false if maximum_version && version > Gem::Version.new(maximum_version)
            return true
          end
          false
        end

        # Already patched? Delegates to patcher
        def patched?
          patcher.patched?
        end

        # Apply instrumentation (idempotent). Delegates to patcher
        def patch!(tracer_provider: nil)
          return false unless available? && compatible?
          patcher.patch!(tracer_provider)
        end

        # The patcher class (must inherit from Patcher base class)
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

### `lib/braintrust/contrib/patcher.rb`

Base class for all patchers with thread-safe patching:

```ruby
# lib/braintrust/contrib/patcher.rb
module Braintrust
  module Contrib
    # Context passed to perform_patch - extensible without breaking signatures
    PatchContext = Struct.new(:tracer_provider, keyword_init: true)

    # Base class for all patchers
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
              tracer_provider: tracer_provider
            )

            perform_patch(context)
            @patched = true
          end
          Braintrust::Log.debug("Patched #{name}")
          true
        rescue => e
          Braintrust::Log.error("Failed to patch #{name}: #{e.message}")
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

## Files to Modify

### `lib/braintrust.rb`

Add require for contrib framework:

```ruby
# Add after other requires
require_relative "braintrust/contrib"
```

## Tests to Create

### `test/braintrust/contrib/registry_test.rb`

- Test registration of integrations
- Test lookup by name
- Test `available` filtering
- Test `integrations_for_require_path` caching and thread-safety

### `test/braintrust/contrib/integration_test.rb`

- Test `available?` with mock gem specs
- Test `compatible?` with version constraints
- Test `patched?` delegation to patcher
- Test `patch!` delegation and return values

### `test/braintrust/contrib/patcher_test.rb`

- Test idempotency (calling patch! twice)
- Test thread-safety (concurrent patch! calls)
- Test error handling (perform_patch raises)

## Documentation

Add brief section to README on contrib architecture (can be expanded in later milestones).

## Dependencies

None - this is the foundation milestone.

## Thread Safety Summary

| Component | Issue | Solution |
|-----------|-------|----------|
| Registry cache | Race condition reading `@require_path_map` | Double-checked locking pattern |
| Patcher `patch!` | Race condition setting `@patched` | Mutex with double-check |
