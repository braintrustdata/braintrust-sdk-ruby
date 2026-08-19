# VCR Cassettes

This directory contains VCR cassette files that record and replay HTTP interactions for tests.

## Do NOT hand-craft cassette YAML files

Cassette files must be **recorded from real API responses**, not written by hand. Hand-crafted cassettes contain plausible but fake data — they produce tests that pass locally against invented responses but silently diverge from what real APIs actually return. This defeats the purpose of integration testing.

## How to record cassettes

You need a real API key in the environment. Check `.env.example` for which keys are needed.

```bash
# Record cassettes for a specific appraisal + test file (fastest)
VCR_MODE=all bundle exec appraisal <name> ruby -Ilib:test test/braintrust/contrib/<name>/instrumentation/..._test.rb

# Re-record all cassettes for an appraisal scenario
VCR_MODE=all bundle exec appraisal <name> rake test

# Record only new cassettes, keep existing ones
VCR_MODE=new_episodes bundle exec appraisal <name> rake test
```

VCR filters sensitive data automatically (see `test/test_helper.rb` — API keys are replaced with placeholder strings before saving).

## Cassette lifecycle

| Mode | Behavior |
|------|----------|
| `:once` (default) | Record if missing, replay if present. Never re-records. |
| `VCR_MODE=all` | Always re-record, overwriting existing cassettes. |
| `VCR_MODE=new_episodes` | Record new interactions, replay existing ones. |
| `VCR_OFF=true` | Disable VCR entirely — makes real HTTP requests every run. |

## Directory structure

Cassettes mirror the test directory structure under `contrib/`:

```
vcr_cassettes/
  contrib/
    openai/
    anthropic/
    ruby_llm/
    llm_rb/
    ...
```

Each subdirectory corresponds to one integration. Cassette filenames match the `VCR.use_cassette(...)` call in the test.
