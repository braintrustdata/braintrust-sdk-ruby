---
name: fix-integration-bug
description: Workflow for fixing bugs in Ruby SDK integrations. Covers reproducing the bug, using appraisals, adding test cases, and TDD-based fixes.
---

# Fixing Integration Bugs

**This skill is for fixing bugs in existing integrations.** Follow this workflow to reproduce, test, and fix integration issues.

## 1. Reproduce the Bug

First, understand and reproduce the issue:

```bash
# Run with console logging to see actual trace output
BRAINTRUST_ENABLE_TRACE_CONSOLE_LOG=true bundle exec appraisal provider ruby examples/provider.rb

# Or create a minimal reproduction script
BRAINTRUST_ENABLE_TRACE_CONSOLE_LOG=true bundle exec appraisal provider ruby -e '
  require "braintrust"
  # minimal reproduction code
'
```

## 2. Appraisal Commands

Test against specific gem versions:

```bash
# Install dependencies for all appraisals
bundle exec appraisal install

# Run tests for specific appraisal
bundle exec appraisal provider rake test

# Run single test file
bundle exec appraisal provider rake test TEST=test/braintrust/trace/provider_test.rb

# Run with specific seed (useful for reproducing flaky test failures from CI)
bundle exec appraisal provider rake test[12345]

# Run all appraisals
bundle exec appraisal rake test

# Re-record VCR cassettes
VCR_MODE=all bundle exec appraisal provider rake test
```

## 3. Add Failing Test Case

Write a test that reproduces the bug:

```ruby
def test_bug_description
  # Arrange: Set up the scenario that triggers the bug

  # Act: Call the method

  # Assert: Verify expected behavior (this should FAIL initially)
end
```

## 4. Add Example Case (if applicable)

Add a case to the internal example that exercises the buggy code path:

- **Location**: `examples/internal/provider.rb`
- **Purpose**: Demonstrates the fix works end-to-end
- Follow existing example patterns (nest under root span, print output)

## 5. TDD Fix Cycle

1. Run failing test: `bundle exec appraisal provider rake test`
2. Implement minimal fix in `lib/braintrust/trace/contrib/provider.rb`
3. Run tests again (should pass)
4. Lint: `bundle exec rake lint:fix`
5. Run all appraisals: `bundle exec appraisal rake test`

## 6. Verify with MCP

Query traces to confirm the fix:

```ruby
mcp__braintrust__btql_query(query: "SELECT input, output, metrics FROM project_logs LIMIT 5")
```

## Reference Files

- Integrations: `lib/braintrust/trace/contrib/{openai,anthropic,ruby_llm}.rb`
- Tests: `test/braintrust/trace/{openai,anthropic,ruby_llm}_test.rb`
- Examples: `examples/internal/{openai,anthropic,ruby_llm}.rb`
- VCR cassettes: `test/fixtures/vcr_cassettes/provider/`
