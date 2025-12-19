# Spike Next Steps

The spike for milestones 3-6 is complete. All behaviors have been proven viable. This document tracks the remaining work to bring the spike code to production quality.

## Files Created/Modified in Spike

| File | Change |
|------|--------|
| `lib/braintrust.rb` | Added `auto_instrument:` param to `init()`, `perform_auto_instrument` method |
| `lib/braintrust/contrib.rb` | Added `auto_instrument!` method |
| `lib/braintrust/contrib/auto_instrument.rb` | New file - require-time auto-instrumentation |
| `lib/braintrust/internal/env.rb` | New file - environment variable parsing utility |
| `exe/braintrust` | New file - CLI wrapper |

## Quality Work Remaining

### Tests

- [ ] `test/braintrust/contrib_test.rb` - Test `auto_instrument!` with various filter combinations
- [ ] `test/braintrust/init_auto_instrument_test.rb` - Test `init(auto_instrument: ...)` variations
- [ ] `test/braintrust/contrib/auto_instrument_test.rb` - Test require hook, Rails hook, idempotency
- [ ] `test/braintrust/cli_test.rb` - Test CLI option parsing, RUBYOPT injection, error handling
- [ ] `test/braintrust/internal/env_test.rb` - Test `Env.parse_list`

### Gemspec

- [ ] Add `spec.executables = ["braintrust"]` to register CLI
- [ ] Verify gem builds correctly with new files

### Documentation

- [ ] Update README with auto-instrumentation examples
- [ ] Document environment variables
- [ ] Add CLI usage section

### Edge Cases & Robustness

- [ ] Review thread safety of require hook (reentrancy guard exists but needs testing)
- [ ] Test behavior when integration is already patched (idempotency)
- [ ] Test behavior with missing API key (should fail gracefully)
- [ ] Test `--only` and `--except` CLI flags end-to-end
- [ ] Test Rails `after_initialize` hook (mock Rails environment)

### Code Quality

- [ ] Add `frozen_string_literal: true` to all new files (already done)
- [ ] Review error messages for clarity
- [ ] Consider extracting CLI logic into `lib/braintrust/cli.rb` for better organization
- [ ] Add YARD documentation to public methods

## Open Questions

1. **Bundler detection in CLI**: Currently we document that users should use `bundle exec braintrust`. Should we try to detect bundler and inject `-rbundler/setup` automatically?

2. **Silent failures**: `auto_instrument.rb` rescues errors from `Braintrust.init`. Is this the right behavior, or should we log warnings?

3. **Require hook cleanup**: The require hook permanently modifies `Kernel.require`. Should we provide a way to remove it?

## Running the Spike

To verify the spike works:

```bash
# Test auto_instrument!
bundle exec appraisal openai ruby -e "
  require 'openai'
  require 'braintrust'
  result = Braintrust::Contrib.auto_instrument!
  puts result.inspect  # => [:openai]
"

# Test init auto_instrument
bundle exec appraisal openai ruby -e "
  require 'openai'
  require 'braintrust'
  Braintrust.init
  puts Braintrust::Contrib::OpenAI::ChatPatcher.patched?  # => true
"

# Test CLI
bundle exec braintrust exec -- ruby -e "
  require 'openai'
  puts Braintrust::Contrib::OpenAI::ChatPatcher.patched?  # => true
"
```
