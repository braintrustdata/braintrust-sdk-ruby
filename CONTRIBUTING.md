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

## Adding integrations for libraries

To add instrumentation support for a new library, use the integration generator:

```bash
rake contrib:generate NAME=trustybrain_llm AUTO_REGISTER=true
```

This will create the integration structure and optionally register it. You can also specify additional options:

```bash
rake contrib:generate NAME=trustybrain_llm \
  GEM_NAMES=trustybrain_llm,trustybrain \
  REQUIRE_PATHS=trustybrain \
  MIN_VERSION=1.0.0 \
  MAX_VERSION=2.0.0 \
  AUTO_REGISTER=true
```

### Manual Setup

If you prefer to create the integration manually, follow these steps:

### 1. Create the integration directory structure

```bash
mkdir -p lib/braintrust/contrib/trustybrain_llm
mkdir -p test/braintrust/contrib/trustybrain_llm
```

### 2. Define the integration stub

Create `lib/braintrust/contrib/trustybrain_llm/integration.rb`:

```ruby
# frozen_string_literal: true

require_relative "../integration"

module Braintrust
  module Contrib
    module TrustybrainLLM
      class Integration
        include Braintrust::Contrib::Integration

        def self.integration_name
          :trustybrain_llm
        end

        def self.gem_names
          ["trustybrain_llm"]
        end

        def self.patchers
          require_relative "patcher"
          [Patcher]
        end
      end
    end
  end
end
```

### 3. Create the patcher

Create `lib/braintrust/contrib/trustybrain_llm/patcher.rb`:

```ruby
# frozen_string_literal: true

require_relative "../patcher"

module Braintrust
  module Contrib
    module TrustybrainLLM
      class Patcher < Braintrust::Contrib::Patcher
        class << self
          def applicable?
            defined?(::TrustybrainLLM::Client)
          end

          def perform_patch(**options)
            ::TrustybrainLLM::Client.prepend(Instrumentation)
          end
        end

        module Instrumentation
          def chat(*args, **kwargs, &block)
            Braintrust::Contrib.tracer_for(self).in_span("trustybrain_llm.chat") do
              super
            end
          end
        end
      end
    end
  end
end
```

### 4. Register it

Add to `lib/braintrust/contrib.rb`:

```ruby
require_relative "contrib/trustybrain_llm/integration"

# At the bottom:
Contrib::TrustybrainLLM::Integration.register!
```

### 5. Write tests

Create test files in `test/braintrust/contrib/trustybrain_llm/`:

```ruby
# test/braintrust/contrib/trustybrain_llm/integration_test.rb
require "test_helper"

class Braintrust::Contrib::TrustybrainLLM::IntegrationTest < Minitest::Test
  def test_integration_basics
    integration = Braintrust::Contrib::TrustybrainLLM::Integration
    assert_equal :trustybrain_llm, integration.integration_name
    assert_equal ["trustybrain_llm"], integration.gem_names
  end

  # TODO: Add tests for patchers, availability, compatibility, and instrumentation
end
```

See existing tests in `test/braintrust/contrib/` for complete examples.
