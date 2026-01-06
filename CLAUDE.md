# Braintrust Ruby SDK

Ruby SDK for Braintrust observability (tracing, evals, logging).

## Code Structure

- `lib/braintrust/` - Main SDK code
  - `trace.rb`, `trace/` - Tracing/spans for LLM calls
  - `eval.rb`, `eval/` - Evaluation framework
  - `api.rb`, `api/` - API client
  - `state.rb` - Global state management
- `test/` - Tests mirror lib/ structure
- `examples/` - Usage examples

## Commands

```bash
rake              # Run lint + all appraisal tests (CI)
rake test         # Run tests
rake lint         # StandardRB linter
rake lint:fix     # Auto-fix lint issues
rake -T           # List all tasks
```

## TDD

Reproduce the issue in a failing test before fixing it.

## Testing

**Prefer real code over mocks.** Use VCR to record/replay HTTP interactions.

```bash
rake test                    # Run with VCR cassettes
VCR_MODE=all rake test       # Re-record all cassettes
VCR_MODE=new_episodes rake test  # Record new, keep existing
```

### Appraisals (Optional Dependencies)

The SDK integrates with optional gems (openai, anthropic, ruby_llm). Tests run against multiple versions:

```bash
bundle exec appraisal list                    # Show scenarios
bundle exec appraisal openai rake test        # Test with openai gem
bundle exec appraisal openai-uninstalled rake test  # Test without
```

## Linting

Uses StandardRB. Run `rake lint:fix` before committing.
