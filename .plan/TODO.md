# Braintrust Ruby SDK - TODO

> See `.DONE.md` for completed work

## High Priority - Next Steps

### 1. LLM Provider Integrations
- [x] **OpenAI Integration** ✅ COMPLETE
  - SDK works without openai gem installed (appraisal "openai-uninstalled")
  - OpenAI integration is opt-in via `require "braintrust/trace/openai"`
  - Tests pass with multiple OpenAI versions: 0.33.x, 0.34.x, latest
  - Appraisals configured in CI pipeline
- [x] **Anthropic Integration** ✅ COMPLETE (v0.0.3)
  - Full Claude API support (messages.create + messages.stream)
  - Anthropic-specific token accounting (cache_creation_input_tokens, cache_read_input_tokens)
  - System prompts, tool use, vision, streaming with SSE aggregation
  - SDK works without anthropic gem installed (appraisal "anthropic-uninstalled")
  - Tests pass with multiple Anthropic versions: 1.11.x, 1.12.x, latest
  - Examples: basic usage + kitchen sink (6 scenarios)
  - CI configured with ANTHROPIC_API_KEY
  - Coverage: 88.79% line, 61.05% branch
- [x] **Attachments** ✅ COMPLETE
  - Manual attachment API for logging binary data (images, PDFs, audio, etc.)
  - Factory methods: `from_bytes`, `from_file`, `from_url`
  - Ruby-idiomatic conversion: `to_data_url`, `to_message`, `to_h`
  - Reusable attachments (no single-use restriction)
  - Module: `Braintrust::Trace::Attachment`
  - Full test coverage (11 tests, all passing)
  - Example: `examples/trace/trace_attachments.rb`
  - Documentation: YARD docs + README section

### 2. Validate Optional Dependencies & Version Support
- [x] **Validate oldest sane OpenTelemetry version** ✅ COMPLETE
  - Updated gemspec: `opentelemetry-sdk ~> 1.3`, `opentelemetry-exporter-otlp ~> 0.28`
  - Minimum versions (due to dependency constraints):
    - opentelemetry-sdk 1.3.0 (June 2023, ~2.4 years old)
    - opentelemetry-exporter-otlp 0.28.0 (June 2024, ~1.5 years old)
  - Added appraisals: `opentelemetry-min` and `opentelemetry-latest`
  - All 168 tests pass with minimum versions (sdk 1.3.2, exporter 0.28.1)
  - All 168 tests pass with latest versions (sdk 1.10.0, exporter 0.31.1)
  - CI automatically tests all appraisals including both min and latest versions
- [ ] **Test SDK behavior with/without tracing**
  - Add tests with `tracing: false` parameter
  - Verify API client works without tracing (datasets, functions)
  - Verify login works without tracing
  - Verify Evals work without tracing (or graceful degradation)
  - Test that `Trace.enable` raises clear error if called with tracing: false
- [ ] **Goal**: Ensure SDK is resilient and has minimal required dependencies



## Medium Priority

### Try to autuoinstument

one method call braintrust.init(:autoinstrument=true) will automatically patch
all contrib wrappers.

### Test Coverage Improvement
- [ ] Increase coverage from 93.81% → 95%+ target
  - Current: 93.81% line (742/791), 72.16% branch (210/291)
  - Increased from 88.79% due to AI span filtering implementation
  - 157 tests, 393 assertions, all passing
- [ ] Focus on under-tested areas:
  - API client edge cases (error responses, pagination)
  - Error handling paths
  - Optional parameter variations
  - Anthropic streaming aggregation edge cases (VCR limitations)
  - OpenAI wrapper edge cases


### Documentation for v0.1.0
- [x] YARD documentation scaffolding (rake yard task, .yardopts, badges) ✅
  - Current: 87.5% documented (auto-published to gemdocs.org)
- [ ] Complete YARD documentation for remaining undocumented APIs
  - 4 undocumented modules
  - 5 undocumented methods
  - Add more @example tags for better usage examples
- [ ] Tag v0.1.0 release
  - Currently at v0.0.2 in lib/braintrust/version.rb
  - Waiting on dependency validation and testing

## Low Priority

### Parallelism
- [ ] Implement parallel execution in Eval.run
  - Currently runs cases sequentially
  - Need to implement with threads or concurrent-ruby
  - Parameter already exists but isn't used

### OpenAI Additional Endpoints
- [ ] Embeddings support
- [ ] Assistants API support
- [ ] Fine-tuning API support
- [ ] Images API support

### OpenAI Error Handling & Reliability
- [ ] Better error handling for API failures
- [ ] Retry logic with exponential backoff
- [ ] Timeout configuration
- [ ] Rate limiting handling

## Deferred Items

- [ ] API::Projects (move from Internal::Experiments)
- [ ] API::Experiments (move from Internal::Experiments)
- [ ] Implement Braintrust.with_state (not needed yet)
