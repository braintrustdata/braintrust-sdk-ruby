# Contributing to Braintrust Ruby SDK

Thanks for contributing! Follow TDD practices: write tests first, implement minimal code, refactor.

## Quick Setup

```bash
# Clone repo
git clone git@github.com:braintrustdata/braintrust-sdk-ruby.git
cd braintrust-sdk-ruby

# Install system dependencies
./scripts/install-deps.sh

# Install mise (if needed)
curl https://mise.run | sh
# Add to shell: eval "$(mise activate bash)"  # or zsh

# Install Ruby + tools (also runs bundle install)
mise install

# Copy .env and add API keys
cp .env.example .env

# Verify setup
rake
```

## Development

```bash
rake test              # Run tests
rake lint              # Check style
rake lint:fix          # Auto-fix style
mise run watch-test    # Watch mode
```

## Testing

- Use Minitest with plain `assert` statements
- Test both global and explicit state
- Aim for 80%+ coverage

## Pull Requests

1. Create feature branch
2. Write tests first (TDD)
3. Ensure `rake` passes (tests + lint)
4. Update CHANGELOG.md if user-facing
5. Create PR

## Troubleshooting

**Ruby won't compile**: Run `./scripts/install-deps.sh`
**Linter fails**: Run `rake lint:fix`
**Tests fail**: Run `bundle install`
