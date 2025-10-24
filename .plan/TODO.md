# Braintrust Ruby SDK - TODO

> See `.DONE.md` for completed work

## High Priority - Next Steps

### 1. Validate Optional Dependencies & Version Support
- [ ] **Validate OpenAI gem is NOT a runtime dependency** ✅ (currently dev-only)
  - Ensure SDK works without openai gem installed
  - OpenAI integration is opt-in via `require "braintrust/trace/openai"`
  - Add test that verifies SDK loads without openai gem
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

### Test Coverage Improvement
- [ ] Increase coverage from 91% → 95%+ target
  - Current: 91.48% (805/880 lines)
  - Focus on edge cases and error paths
- [ ] Focus on under-tested areas:
  - API client edge cases (error responses, pagination)
  - Error handling paths
  - Optional parameter variations
  - OpenAI wrapper edge cases

### Span Filtering Logic
- [ ] Implement span filtering (AI spans filter)
  - Filter spans based on type (e.g., only export AI-related spans)
  - Configurable filtering rules
  - Integration with span processor

### Documentation for v0.1.0
- [ ] Document all public APIs (RDoc/YARD documentation)
  - Some inline docs exist but not comprehensive
- [ ] Add inline code comments
  - Core files have basic comments, needs expansion
- [ ] Tag v0.1.0 release
  - Still at v0.0.1 in lib/braintrust/version.rb
  - Waiting on coverage and dependency validation

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
