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

### Testing with Different Ruby Versions

CI tests against Ruby 3.2, 3.3, and 3.4. To test locally with a different Ruby version:

```bash
# Install a different Ruby version
mise install ruby@3.4

# Run tests with that version
mise exec ruby@3.4 -- bundle install
mise exec ruby@3.4 -- bundle exec rake test

# Run appraisal tests with that version
mise exec ruby@3.4 -- bundle exec appraisal install
mise exec ruby@3.4 -- bundle exec appraisal openai-0-33 rake test
```

To temporarily switch your shell to a different Ruby:

```bash
mise use ruby@3.4
ruby --version  # => 3.4.x
bundle exec rake test
```
