# Contributing to Braintrust Ruby SDK

Thanks for contributing! Follow TDD practices: write tests first, implement minimal code, refactor.

- [Quick Setup](#quick-setup)
  - [Local development (on host)](#local-development-on-host)
  - [Local development (in Docker)](#local-development-in-docker)
- [Development](#development)
  - [Running tasks](#running-tasks)
  - [Adding new integrations for AI Libraries](#adding-new-integrations-for-ai-libraries)
- [Testing](#testing)
  - [With different Ruby versions](#with-different-ruby-versions)

## Quick Setup

### Local development (on host)

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

### Local development (in Docker)

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

### Running tasks

All of our common dev tasks are in rake.

```bash
rake -T 
```

### Adding new integrations for AI Libraries

To add instrumentation support for a new AI library, follow these steps:

#### 1. Define the Integration

Create a new file in `lib/braintrust/contrib/`:

```ruby
# lib/braintrust/contrib/trustybrain_llm.rb
module Braintrust::Contrib
  class TrustybrainLLM
    include Integration

    def self.integration_name
      :trustybrain_llm
    end

    def self.gem_names
      ["trustybrain_llm"]
    end

    def self.patcher
      TrustybrainLLMPatcher
    end
  end

  class TrustybrainLLMPatcher < Patcher
    def self.perform_patch(context)
      # Add your instrumentation here
      # context.tracer_provider gives you access to the tracer
    end
  end
end
```

#### 2. Register It

Add to `lib/braintrust/contrib.rb`:

```ruby
require_relative "contrib/trustybrain_llm"

# At the bottom:
Contrib::TrustybrainLLM.register!
```

#### 3. Write Tests

Create `test/braintrust/contrib/trustybrain_llm_test.rb`:

```ruby
require "test_helper"

class Braintrust::Contrib::TrustybrainLLMTest < Minitest::Test
  def test_integration_basics
    assert_equal :trustybrain_llm, TrustybrainLLM.integration_name
    assert_equal ["trustybrain_llm"], TrustybrainLLM.gem_names
  end
end
```

See existing tests in `test/braintrust/contrib/` for complete examples of testing integrations, patchers, and the registry.

## Testing

We use VCR for making http tests fast. You can run tests with these enabled,
off, etc. If you add new tests you'll need to record new cassettes. See this
for more details.

```bash
rake -T test:vcr
```

### With different Ruby versions

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

