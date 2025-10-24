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

All of our common dev tasks are in rake.

```bash
rake -T 
```

## Testing

We use VCR for making http tests fast. You can run tests with these enabled,
off, etc. If you add new tests you'll need to record new cassettes. See this
for more details.

```bash
rake -T test:vcr
```
