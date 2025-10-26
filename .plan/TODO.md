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

### 2. Validate Optional Dependencies & Version Support
- [ ] **Validate oldest sane OpenTelemetry version**
  - Current: `opentelemetry-sdk ~> 1.0`, `opentelemetry-exporter-otlp ~> 0.28`
  - Research oldest stable versions (1.0+ for SDK, 0.28+ for exporter?)
  - Test with minimum versions to ensure compatibility
  - Consider widening version constraints if safe (e.g., `>= 1.0, < 2.0`)
  - Document minimum supported versions in README
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
- [ ] Increase coverage from 88.79% → 95%+ target
  - Current: 88.79% line (1014/1142), 61.05% branch (301/493)
  - Decreased from 91.48% due to new Anthropic integration code
  - 143 tests, 550 assertions, all passing
- [ ] Focus on under-tested areas:
  - API client edge cases (error responses, pagination)
  - Error handling paths
  - Optional parameter variations
  - Anthropic streaming aggregation edge cases (VCR limitations)
  - OpenAI wrapper edge cases

### Span Filtering Logic
- [ ] Implement span filtering (AI spans filter)
  - Filter spans based on type (e.g., only export AI-related spans)
  - Configurable filtering rules
  - Integration with span processor

### Documentation for v0.1.0
- [x] YARD documentation scaffolding (rake yard task, .yardopts, badges) ✅
  - Current: 87.5% documented (auto-published to rubydoc.info)
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
