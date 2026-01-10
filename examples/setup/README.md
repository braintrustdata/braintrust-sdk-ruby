# Setup Examples

These examples demonstrate different ways to automatically setup the Braintrust SDK.

## Local Development

When running examples from the repo (gem not installed), use these commands:

```bash
# For init.rb and require.rb examples:
OPENAI_API_KEY=your-key ANTHROPIC_API_KEY=your-key \
  bundle exec appraisal contrib ruby examples/setup/init.rb

# For exec.rb examples (reference exe/braintrust directly):
OPENAI_API_KEY=your-key ANTHROPIC_API_KEY=your-key \
  bundle exec appraisal contrib exe/braintrust exec -- \
  ruby examples/setup/exec.rb
```

## Examples

| File         | Approach                         | Code Changes Required |
| ------------ | -------------------------------- | --------------------- |
| `init.rb`    | `Braintrust.init`                | Add init call         |
| `require.rb` | `require "braintrust/setup"`     | Add require           |
| `exec.rb`    | `braintrust exec -- ruby app.rb` | None                  |
