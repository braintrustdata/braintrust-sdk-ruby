# Braintrust Ruby SDK - Architecture & Design

## Overview

Ruby SDK for Braintrust based on OpenTelemetry, modeled after the braintrust-x-go implementation. Provides:
- OpenTelemetry-based tracing with automatic Braintrust integration
- OpenAI client instrumentation via Faraday middleware
- Evaluation framework for AI model testing

## Core Design: State Management

Hybrid approach inspired by Python libraries - supports both global state and explicit state passing.

### API Pattern

```ruby
# Simple case - sets global state (default)
Braintrust.init(
  api_key: ENV['BRAINTRUST_API_KEY'],
  project: "my-project"
)

# Explicit state (for testing, multi-tenant)
state = Braintrust.init(
  api_key: "key",
  project: "project",
  set_global: false
)

# All APIs accept optional state, fall back to global
Braintrust::Trace.enable(state)  # explicit
Braintrust::Trace.enable         # uses global

api = Braintrust::API.new(state)  # explicit
api = Braintrust::API.new         # uses global
```

### State Object

Holds configuration and initialized resources:
- `api_key` - Braintrust API key
- `org_name` - Organization name
- `project_id` - Default project ID
- `project_name` - Default project name
- `app_url` - Braintrust app URL
- `tracer_provider` - OpenTelemetry tracer provider instance

## Module Architecture

### Braintrust (Main Module)

**lib/braintrust.rb**

Entry point for the SDK. Manages global state.

```ruby
Braintrust.init(options)          # Initialize and optionally set global
Braintrust.current_state          # Get global state
Braintrust.with_state(state)      # Temporarily override state
```

### Braintrust::State

**lib/braintrust/state.rb**

State container with login support.

- Thread-safe global state management
- Merges ENV vars with explicit options
- Validates required fields (api_key required)
- Mutable to allow login() to update org info
- login() method fetches org details from Braintrust API
- Holds org_id, org_name, api_url, proxy_url after login
- Will hold tracer_provider instance (Phase 3)

### Braintrust::Config

**lib/braintrust/config.rb**

Configuration and ENV var handling.

ENV vars:
- `BRAINTRUST_API_KEY` - API key
- `BRAINTRUST_ORG_NAME` - Organization name
- `BRAINTRUST_DEFAULT_PROJECT_ID` - Default project ID
- `BRAINTRUST_DEFAULT_PROJECT_NAME` - Default project name
- `BRAINTRUST_APP_URL` - App URL (default: https://www.braintrust.dev)
- `BRAINTRUST_API_URL` - API URL (default: https://api.braintrust.dev)
- `BRAINTRUST_DEBUG` - Enable debug logging
- `BRAINTRUST_ENABLE_TRACE_CONSOLE_LOG` - Enable console trace logging (Phase 3)

### Braintrust::Trace

**lib/braintrust/trace.rb**

OpenTelemetry integration.

```ruby
teardown = Braintrust::Trace.enable(state = nil)
# ... your code with tracing
teardown.call
```

Creates:
- OTLP HTTP exporter to Braintrust
- Custom span processor for Braintrust attributes
- Registers with OpenTelemetry

### Braintrust::Trace::SpanProcessor

**lib/braintrust/trace/span_processor.rb**

Custom OpenTelemetry span processor.

Features:
- Adds `braintrust.parent` attribute (project_name:X, experiment_id:X, etc.)
- Adds `braintrust.org` and `braintrust.app_url` attributes
- Resolves parent from context if set via `Braintrust::Trace.set_parent(context, parent)`
- Filters spans (optionally keep only AI spans)

### Braintrust::Trace::OpenAI

**lib/braintrust/trace/openai.rb**

Faraday middleware for OpenAI client instrumentation.

```ruby
client = OpenAI::Client.new(
  access_token: ENV['OPENAI_API_KEY'],
  faraday_middleware: Braintrust::Trace::OpenAI.middleware(state)
)
```

Features:
- Automatic span creation for chat.completions
- Records request/response as span attributes
- Parses and records token usage metrics
- Maps to gen_ai.* semantic conventions
- Handles streaming responses

### Braintrust::Eval

**lib/braintrust/eval.rb**

Evaluation framework.

```ruby
result = Braintrust::Eval.run(
  state: state,        # optional
  experiment: "name",
  cases: [...],
  task: ->(input) { ... },
  scorers: [...],
  tags: [...],
  metadata: {...},
  parallelism: 5
)
```

Features:
- Auto-resolves project and experiment IDs via API
- Parallel execution with configurable thread count
- Creates OpenTelemetry spans for eval/task/score
- Returns result with permalink

### Braintrust::Eval::Scorer

**lib/braintrust/eval/scorer.rb**

Scorer interface and helpers.

```ruby
# Using the helper
scorer = Braintrust::Eval.scorer("equals") do |input, expected, result, metadata|
  result == expected ? 1.0 : 0.0
end

# Or implement the interface
class MyScorer
  def name
    "my_scorer"
  end

  def call(input, expected, result, metadata)
    # return score (0.0 to 1.0)
  end
end
```

### Braintrust::API

**lib/braintrust/api.rb**

HTTP client for Braintrust API.

```ruby
api = Braintrust::API.new(state)
project = api.register_project(name)
experiment = api.register_experiment(name, project_id, options)
dataset = api.create_dataset(project_id, name, description)
```

## Design Decisions

### 1. State Management

**Decision**: Hybrid global + explicit state approach

**Rationale**:
- Simple cases don't need to pass state around
- Testing and multi-tenant scenarios can use explicit state
- Matches patterns from successful Python libraries
- Avoids global state issues in Go SDK

### 2. OpenTelemetry Integration

**Decision**: Users interact with OpenTelemetry directly for tracing

**Rationale**:
- Standard observability interface
- Works with existing OTEL instrumentation
- Braintrust adds span processor for metadata
- No custom tracing API to learn

### 3. OpenAI Integration via Faraday

**Decision**: Faraday middleware for instrumentation

**Rationale**:
- ruby-openai uses Faraday internally
- Middleware pattern is clean and non-invasive
- Can intercept requests/responses without patching
- Easy to add/remove

### 4. Thread-based Parallelism for Evals

**Decision**: Use Ruby threads for parallel execution

**Rationale**:
- Simple and built-in
- Sufficient for I/O-bound eval tasks
- No external dependencies
- Can add Ractor support later if needed

## Testing Strategy

### Test Helpers

**test/test_helper.rb**

Utilities for testing:
- Mock OTEL span exporter for capturing spans
- State setup/teardown helpers
- Custom assertions for span attributes
- Mock API responses

### Test Coverage Targets

- 80%+ overall coverage
- 100% for critical paths (state management, span processor)
- Integration tests with real OTEL setup
- Thread safety tests
- Both global and explicit state scenarios

## Dependencies

### Runtime
**Note**: Runtime dependencies are added incrementally as features are implemented:
- Phase 3: `opentelemetry-sdk`, `opentelemetry-exporter-otlp`
- Phase 4: `ruby-openai`, `faraday`
- Phase 5: HTTP client for Braintrust API

### Development
- `minitest` (~> 5.0) - Testing framework
- `rake` (~> 13.0) - Task automation
- `standard` (~> 1.0) - Linting (zero-config)
- `simplecov` (~> 0.22) - Code coverage

### Tools (via mise)
- Ruby 3.2 (pinned for development)
- Rust 1.83 (for Ruby compilation)
- watchexec - File watching for tests

## Key Differences from Go SDK

1. **State Management**: Hybrid global/explicit vs pure global (avoids Go SDK's global state issues)
2. **API Style**: Ruby blocks/procs vs Go functions
3. **Middleware**: Faraday vs HTTP middleware
4. **Parallelism**: Threads vs goroutines
5. **Testing**: Minitest vs testify
6. **Linting**: Standard (zero-config) vs golangci-lint
7. **Dependencies**: Added incrementally as needed vs upfront

## Implementation Notes

### Session 1 (2025-10-21)

**Completed**:
- Full project infrastructure (gemspec, Rakefile, CI/CD)
- mise.toml with automatic bundle install and precommit hooks
- Cross-platform dependency installer (scripts/install-deps.sh)
- Minimal docs (README.md, CONTRIBUTING.md)
- Moved tracking docs to hidden files (.PLAN.md, .TODO.md)
- Added `rake ci` task for CI verification
- Removed build/release tasks (will add when ready to publish)
- Created main branch
- Config class with ENV parsing and option merging
- State class with thread-safe global state management
- Braintrust.init with set_global option

**Decisions**:
- Runtime deps added only when needed (not all upfront)
- Standard linter (zero-config, opinionated)
- Minitest (Ruby built-in, plain asserts)
- Simplified docs (essentials only)
- No system gem installation tasks
- mise handles Ruby + Rust, brew handles C libraries
- Hybrid state management (global + explicit state)
- Mutable state (removed freeze to allow login to update fields)

### Session 2 (2025-10-21)

**Completed**:
- Login API integration (lib/braintrust/api/auth.rb)
  - AuthResult struct with org_id, org_name, api_url, proxy_url
  - Proper HTTP error handling (401/403/400/4xx/5xx)
  - API key masking for logging
- Logger module (lib/braintrust/logger.rb)
  - DEBUG level when BRAINTRUST_DEBUG=true env var set
  - Outputs to stderr
- State#login method
  - Calls API::Auth.login
  - Updates state with org info from API
  - Added org_id, proxy_url, logged_in attributes
- Updated Braintrust.init
  - Added blocking_login parameter
  - Documented all options explicitly (not **options)
- Login example (examples/login/login_basic.rb)
  - Demonstrates blocking_login usage
  - Real API integration tests (no mocks)

**Decisions**:
- Real API tests (not mocks), tests fail if BRAINTRUST_API_KEY not set
- State.login updates current state (doesn't return new state)
- Removed state immutability (freeze) to allow login mutations
- API logic separated into lib/braintrust/api/ module structure
- Struct-based return values (AuthResult) instead of raw hashes
- SSL verification workaround for macOS (VERIFY_NONE with TODO)
- State#login_until_success deferred (background thread with retries)

## Future Enhancements

- Support for additional LLM providers (Anthropic, Google)
- Ractor-based parallelism for better performance
- Dataset management helpers
- Prompt management integration
- Additional built-in scorers
- Streaming response support for evals
