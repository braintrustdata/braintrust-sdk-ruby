# Auto-Instrumentation Examples

These examples demonstrate different ways to automatically instrument LLM libraries with Braintrust.

## Local Development

When running examples from the repo (gem not installed), use these commands:

```bash
# For init.rb and require.rb examples:
OPENAI_API_KEY=your-key ANTHROPIC_API_KEY=your-key \
  bundle exec appraisal auto-instrument ruby examples/contrib/auto_instrument/init.rb

# For exec.rb examples (reference exe/braintrust directly):
OPENAI_API_KEY=your-key ANTHROPIC_API_KEY=your-key \
  bundle exec appraisal auto-instrument exe/braintrust exec -- \
  ruby examples/contrib/auto_instrument/exec.rb
```

## Examples

| File | Approach | Code Changes Required |
|------|----------|----------------------|
| `init.rb` | `Braintrust.init` | Add init call |
| `require.rb` | `require "braintrust/auto_instrument"` | Add require |
| `exec.rb` | `braintrust exec -- ruby app.rb` | None |
