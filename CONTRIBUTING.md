# Contributing to Braintrust Ruby SDK

Thanks for contributing! Follow TDD practices: write tests first, implement minimal code, refactor.

## Quick Setup

### Option 1: Local Development

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

# Install appraisals (for running examples)
bundle exec appraisal install

# Copy .env and add API keys
cp .env.example .env

# Verify setup
rake
```

### Option 2: Docker Container

Use the dev container if you prefer not to install Ruby tooling on your host machine. Your IDE edits files on the host; all tools run in the container.

```bash
# Clone repo
git clone git@github.com:braintrustdata/braintrust-sdk-ruby.git
cd braintrust-sdk-ruby

# Copy .env and add API keys
cp .env.example .env

# Enter interactive shell (first run builds the image)
docker compose run --rm -it dev
```

Once in the dev container, finish setup (same as above):

```bash
# Install Ruby + tools (also runs bundle install)
mise install

# Install appraisals (for running examples)
bundle exec appraisal install

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
