# Auto-Instrumentation Implementation Plan

## Overview
Add automatic instrumentation to `Braintrust.init` so users can enable library tracing without manually calling wrap methods.

## API Design (Final)

### Usage Examples

```ruby
# Enable auto-instrumentation for all available libraries
Braintrust.init(autoinstrument: { enabled: true })

# Only instrument specific libraries (allowlist)
Braintrust.init(autoinstrument: {
  enabled: true,
  include: [:openai, :anthropic]
})

# Instrument all except specific libraries (denylist)
Braintrust.init(autoinstrument: {
  enabled: true,
  exclude: [:ruby_llm]
})

# Disable/default (no auto-instrumentation, manual wrapping only)
Braintrust.init  # autoinstrument omitted (default)
```

### Semantics
- `enabled: true` with no `include:`/`exclude:` → instrument all available libraries
- `enabled: true, include: [...]` → ONLY these (allowlist)
- `enabled: true, exclude: [...]` → all EXCEPT these (denylist)
- Both `include:` and `exclude:` → raise `ArgumentError` (conflicting intent)
- `enabled: false` or omitted → no auto-instrumentation (manual wrapping only)

## Implementation Steps

### 1. Update `Braintrust.init` (lib/braintrust.rb)
- Add `autoinstrument:` parameter (default: `nil`)
- Pass to `State.from_env` and `State#initialize`
- Update YARD documentation

### 2. Update `State` class (lib/braintrust/state.rb)
- Add `attr_reader :autoinstrument_config`
- Parse and validate autoinstrument param in `initialize`:
  - `nil` → `{ enabled: false }`
  - `{ enabled: true }` → `{ enabled: true, include: nil, exclude: nil }`
  - `{ enabled: true, include: [...] }` → store as-is
  - `{ enabled: true, exclude: [...] }` → store as-is
  - `{ enabled: false }` → `{ enabled: false }`
- Validation rules:
  - Raise `ArgumentError` if both `include:` and `exclude:` present
  - Raise `ArgumentError` if `include:`/`exclude:` present without `enabled: true`
  - Raise `ArgumentError` if `include:`/`exclude:` values are not arrays of symbols
- Pass config to `Trace.setup`

### 3. Create `AutoInstrument` module (lib/braintrust/trace/auto_instrument.rb)

```ruby
module Braintrust
  module Trace
    module AutoInstrument
      # Registry of supported libraries
      LIBRARIES = {
        openai: {
          class_name: 'OpenAI::Client',
          wrapper_module: Braintrust::Trace::OpenAI
        },
        anthropic: {
          class_name: 'Anthropic::Client',
          wrapper_module: Braintrust::Trace::Anthropic
        },
        ruby_llm: {
          class_name: 'RubyLLM',
          wrapper_module: Braintrust::Trace::RubyLLM
        }
      }

      # Main entry point for auto-instrumentation
      # @param config [Hash] autoinstrument configuration
      # @param tracer_provider [OpenTelemetry::SDK::Trace::TracerProvider]
      def self.setup(config, tracer_provider)
        return unless config[:enabled]

        libraries_to_instrument = determine_libraries(config)
        libraries_to_instrument.each do |lib|
          instrument_library(lib, tracer_provider)
        end
      end

      private

      # Determine which libraries to instrument based on config
      def self.determine_libraries(config)
        if config[:include]
          config[:include] & LIBRARIES.keys  # Only included libs
        elsif config[:exclude]
          LIBRARIES.keys - config[:exclude]  # All except excluded
        else
          LIBRARIES.keys  # All libraries
        end
      end

      # Instrument a specific library if available
      def self.instrument_library(lib, tracer_provider)
        lib_config = LIBRARIES[lib]
        return unless library_available?(lib_config[:class_name])

        case lib
        when :openai then instrument_openai(tracer_provider)
        when :anthropic then instrument_anthropic(tracer_provider)
        when :ruby_llm then instrument_ruby_llm(tracer_provider)
        end
      rescue => e
        Log.warn("Failed to auto-instrument #{lib}: #{e.message}")
      end

      # Check if library is available
      def self.library_available?(class_name)
        # Use Object.const_defined? to check if class exists
        parts = class_name.split('::')
        parts.reduce(Object) do |mod, part|
          return false unless mod.const_defined?(part)
          mod.const_get(part)
        end
        true
      rescue NameError
        false
      end

      # Instrument OpenAI::Client
      def self.instrument_openai(tracer_provider)
        # Prepend module to OpenAI::Client that wraps initialize
        wrapper = Module.new do
          define_method(:initialize) do |*args, **kwargs, &block|
            super(*args, **kwargs, &block)
            Braintrust::Trace::OpenAI.wrap(self, tracer_provider: tracer_provider)
            self
          end
        end

        ::OpenAI::Client.prepend(wrapper)
        Log.debug("Auto-instrumented OpenAI::Client")
      end

      # Instrument Anthropic::Client
      def self.instrument_anthropic(tracer_provider)
        # Prepend module to Anthropic::Client that wraps initialize
        wrapper = Module.new do
          define_method(:initialize) do |*args, **kwargs, &block|
            super(*args, **kwargs, &block)
            Braintrust::Trace::Anthropic.wrap(self, tracer_provider: tracer_provider)
            self
          end
        end

        ::Anthropic::Client.prepend(wrapper)
        Log.debug("Auto-instrumented Anthropic::Client")
      end

      # Instrument RubyLLM
      def self.instrument_ruby_llm(tracer_provider)
        # Wrap the RubyLLM.chat factory method
        # This is trickier since it returns chat instances
        wrapper = Module.new do
          define_singleton_method(:chat) do
            chat_instance = super()
            Braintrust::Trace::RubyLLM.wrap(chat_instance, tracer_provider: tracer_provider)
            chat_instance
          end
        end

        ::RubyLLM.singleton_class.prepend(wrapper)
        Log.debug("Auto-instrumented RubyLLM.chat")
      end
    end
  end
end
```

### 4. Update `Trace.setup` (lib/braintrust/trace.rb)
- After tracer provider setup, call:
  ```ruby
  AutoInstrument.setup(state.autoinstrument_config, tracer_provider)
  ```
- Require the auto_instrument file

### 5. Update existing wrap methods to prevent double-wrapping

#### OpenAI (lib/braintrust/trace/contrib/openai.rb)
```ruby
def self.wrap(client, tracer_provider: nil)
  # Check if already wrapped
  return client if client.instance_variable_get(:@braintrust_wrapped)

  tracer_provider ||= ::OpenTelemetry.tracer_provider

  # Mark as wrapped
  client.instance_variable_set(:@braintrust_wrapped, true)

  # Existing wrapping logic...
  wrap_chat_completions(client, tracer_provider)
  wrap_responses(client, tracer_provider) if client.respond_to?(:responses)

  client
end
```

#### Anthropic (lib/braintrust/trace/contrib/anthropic.rb)
```ruby
def self.wrap(client, tracer_provider: nil)
  # Check if already wrapped
  return client if client.instance_variable_get(:@braintrust_wrapped)

  tracer_provider ||= ::OpenTelemetry.tracer_provider

  # Mark as wrapped
  client.instance_variable_set(:@braintrust_wrapped, true)

  # Existing wrapping logic...
  wrap_messages_create(client, tracer_provider)
  wrap_messages_stream(client, tracer_provider)

  client
end
```

#### RubyLLM (lib/braintrust/trace/contrib/ruby_llm.rb)
```ruby
def self.wrap(chat, tracer_provider: nil)
  # Check if already wrapped
  return chat if chat.instance_variable_get(:@braintrust_wrapped)

  tracer_provider ||= ::OpenTelemetry.tracer_provider

  # Mark as wrapped
  chat.instance_variable_set(:@braintrust_wrapped, true)

  # Existing wrapping logic...
  # (callback registration code)

  chat
end
```

### 6. Tests (test/braintrust/trace/auto_instrument_test.rb)

Create comprehensive tests covering:

- **Basic functionality:**
  - `enabled: true` instruments all available libraries
  - `include: [:openai]` only instruments OpenAI
  - `exclude: [:ruby_llm]` instruments all except RubyLLM
  - Default behavior (no autoinstrument) unchanged

- **Validation:**
  - Error when both `include:` and `exclude:` specified
  - Error when `include:`/`exclude:` without `enabled: true`
  - Error when `include:`/`exclude:` values are not arrays

- **Double-wrapping prevention:**
  - Manual wrap after autoinstrument is no-op
  - No duplicate spans created

- **Graceful degradation:**
  - Skip libraries that aren't installed
  - Handle errors during instrumentation

- **Integration tests:**
  - Verify spans are created correctly for each library
  - Verify attributes are set properly

### 7. Update documentation

#### README.md
Add new section after "Quick Start":

```markdown
### Auto-Instrumentation

The simplest way to get started is with auto-instrumentation, which automatically traces all supported libraries:

```ruby
require "braintrust"
require "openai"

# Enable auto-instrumentation
Braintrust.init(autoinstrument: { enabled: true })

# All OpenAI calls are now automatically traced!
client = OpenAI::Client.new(api_key: ENV["OPENAI_API_KEY"])
response = client.chat.completions.create(
  model: "gpt-4o-mini",
  messages: [{ role: "user", content: "Hello!" }]
)
```

You can control which libraries are instrumented:

```ruby
# Only instrument specific libraries
Braintrust.init(autoinstrument: {
  enabled: true,
  include: [:openai, :anthropic]
})

# Instrument all except specific libraries
Braintrust.init(autoinstrument: {
  enabled: true,
  exclude: [:ruby_llm]
})
```

Supported libraries: `:openai`, `:anthropic`, `:ruby_llm`
```

#### Update existing examples
- Update `examples/openai.rb` to show autoinstrument option
- Update `examples/anthropic.rb` to show autoinstrument option
- Create `examples/internal/autoinstrument_demo.rb` showing all options

#### YARD documentation
- Add detailed documentation to `Braintrust.init` for `autoinstrument:` parameter
- Document `AutoInstrument` module and its methods
- Update wrap method docs to mention auto-instrumentation

## Backwards Compatibility

✅ **No breaking changes:**
- Default behavior unchanged (autoinstrument disabled by default)
- Manual wrapping still works
- Existing code continues to work without modifications

✅ **Safe to mix:**
- Auto-instrumentation + manual wrapping works (no double-wrap)
- Can selectively enable/disable per library

## Testing Strategy

### Unit Tests
- Test configuration parsing and validation
- Test library detection logic
- Test each instrumentation method in isolation

### Integration Tests
- Test with actual library instances
- Verify spans are created with correct attributes
- Test streaming and non-streaming calls
- Test tool/function calls (RubyLLM)

### VCR Cassettes
- Record API responses for deterministic tests
- Cover all library variations

## Future Enhancements

Potential future additions to the autoinstrument config:

```ruby
Braintrust.init(autoinstrument: {
  enabled: true,
  include: [:openai],
  # Future options:
  # sample_rate: 0.5,  # Sample 50% of traces
  # config: {
  #   openai: { /* library-specific options */ }
  # }
})
```

## Implementation Checklist

- [ ] Update `Braintrust.init` signature
- [ ] Update `State` class with autoinstrument config
- [ ] Create `AutoInstrument` module
- [ ] Implement OpenAI auto-instrumentation
- [ ] Implement Anthropic auto-instrumentation
- [ ] Implement RubyLLM auto-instrumentation
- [ ] Add double-wrap detection to all wrap methods
- [ ] Write comprehensive tests
- [ ] Update README.md
- [ ] Update/create examples
- [ ] Add YARD documentation
- [ ] Manual testing with all libraries
- [ ] Update CHANGELOG.md
