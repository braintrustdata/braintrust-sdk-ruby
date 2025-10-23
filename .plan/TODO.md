# Braintrust Ruby SDK - TODO

> See `.DONE.md` for completed work

## Known Issues / Tech Debt

### High Priority

- [x] **SSL Certificate Verification on macOS**: ✅ FIXED (2025-10-22)
  - **Solution**: Added `openssl` gem v3.3.1+ as runtime dependency
  - Fixed in Ruby/OpenSSL maintainers' release (see https://github.com/ruby/openssl/issues/949)
  - Removed all `VERIFY_NONE` workarounds and ssl_config.rb
  - Now uses proper SSL verification with VERIFY_PEER
  - Tests passing, SSL connections verified working

### Medium Priority

- [x] **Kitchen-Sink Span Export Inconsistency**: ✅ RESOLVED (2025-10-22)
  - Issue was timing-related with concurrent OpenAI API calls
  - Now working correctly

### Low Priority

- [ ] **Parallelism Not Implemented**: Eval.run accepts parallelism parameter but doesn't use it
  - Currently runs cases sequentially
  - Need to implement parallel execution with threads or concurrent-ruby

- [ ] **Testing with/without OpenTelemetry**: Test SDK behavior with optional dependencies
  - Test with OpenTelemetry installed (current default)
  - Test without OpenTelemetry installed (graceful degradation)
  - Test with `tracing: false` parameter
  - Ensure API client, login, and non-tracing features work independently
  - Consider making OpenTelemetry an optional dependency

## Pending Work

### Phase 2: Deferred Items
- [ ] Implement Braintrust.with_state (deferred - not needed yet)
- [x] Implement State#login_in_thread ✅ COMPLETE (2025-10-23) - background thread with retries

### Phase 3: Trace Utilities - ⚠️ MOSTLY COMPLETE
- [x] Write test: permalink generation ✅ COMPLETE (covered in examples)
- [x] Implement Trace.permalink ✅ COMPLETE (2025-10-23 Session 10)
- [x] ~~Trace.set_parent~~ - NOT NEEDED (Go-specific, Ruby uses OpenTelemetry context)
- [x] ~~Trace.get_parent~~ - NOT NEEDED (Go-specific, Ruby uses OpenTelemetry context)
- [ ] Implement span filtering logic (AI spans filter) - NEEDED
  - Filter spans based on type (e.g., only export AI-related spans)
  - Configurable filtering rules
  - Integration with span processor

### Phase 4.5: OpenAI Advanced Features

#### Streaming Support ✅ COMPLETE (2025-10-23)
- [x] Add support for `stream_raw` API
- [x] Handle streaming responses and chunks
- [x] Aggregate streaming data for tracing
- [x] Test streaming with console output
- [x] Proper span parenting with `tracer.start_span`
- [x] Automatic chunk aggregation (100+ lines of logic)
- [x] Usage metrics capture with `stream_options.include_usage`

#### Additional Endpoints
- [ ] Embeddings support
- [ ] Assistants API support
- [ ] Fine-tuning API support
- [ ] Images API support

#### Error Handling & Reliability
- [ ] Better error handling for API failures
- [ ] Retry logic with exponential backoff
- [ ] Timeout configuration
- [ ] Rate limiting handling

### Phase 5: API Client (TDD) - ✅ DATASETS COMPLETE

#### lib/braintrust/api.rb ✅
- [x] Write test: API with explicit state
- [x] Write test: API with global state
- [x] Write test: API#datasets returns Datasets instance
- [x] Implement API class with memoized resource accessors
- [x] Add unique_name() test helper for parallel-safe tests

#### lib/braintrust/api/datasets.rb ✅
- [x] Write test: Datasets#list with project_name
- [x] Write test: Datasets#get by project + name
- [x] Write test: Datasets#get_by_id
- [x] Write test: Datasets#create (idempotent)
- [x] Write test: Datasets#insert events
- [x] Write test: Datasets#fetch with pagination
- [x] Implement Datasets class with all methods
- [x] Implement list, get, get_by_id, create, insert, fetch, permalink
- [x] Implement consolidated http_request() function
- [x] Add debug logging with timing information
- [x] Create examples/api/dataset.rb

#### Deferred (API Projects/Experiments)
- [ ] Write test: register_project creates/fetches project
- [ ] Write test: register_experiment creates experiment
- [ ] Write test: register_experiment with update flag
- [ ] Implement API::Projects
- [ ] Implement API::Experiments
- [ ] Move from Internal::Experiments to public API

### Phase 6: Evals - Remaining Items

#### lib/braintrust/eval.rb
- [ ] Implement parallel execution (parallelism parameter)

#### Auto-print Results ✅ COMPLETE (2025-10-23)
- [x] Add `quiet:` parameter to Eval.run (defaults to false)
- [x] Update Result#to_s to Go SDK format
- [x] Auto-print results via `puts result` unless quiet: true
- [x] Format: Experiment name, ID, Link, Duration, Error count
- [x] Updated all tests to use quiet: true
- [x] Updated examples to rely on auto-printing

#### Dataset Integration ✅ COMPLETE (2025-10-22)
- [x] Add `dataset:` parameter to Eval.run (string or hash)
- [x] Support dataset by name (same project as experiment)
- [x] Support dataset by name + explicit project
- [x] Support dataset by ID
- [x] Support dataset with limit option
- [x] Support dataset with version option
- [x] Auto-pagination (fetch all records by default)
- [x] Validation: dataset and cases are mutually exclusive
- [x] Tests for all dataset features
- [x] Example: examples/eval/dataset.rb

#### Remote Functions ✅ COMPLETE (2025-10-23)
- [x] Write test: API::Functions#list with project_name
- [x] Write test: API::Functions#create with function_data and prompt_data
- [x] Write test: API::Functions#invoke by ID
- [x] Write test: API::Functions#delete
- [x] Implement API::Functions class (lib/braintrust/api/functions.rb)
- [x] Write test: Functions.task returns callable
- [x] Write test: Functions.task invokes remote function
- [x] Write test: Functions.scorer returns Scorer
- [x] Write test: Use remote task in Eval.run
- [x] Implement Eval::Functions module (lib/braintrust/eval/functions.rb)
- [x] Add OpenTelemetry tracing for function invocations (type: "function")
- [x] Make State#login idempotent (returns early if already logged in)
- [x] Add automatic state.login in Eval.run to populate org_name
- [x] Create example: examples/eval/remote_functions.rb
- [x] Add remote scorer with LLM classifier and choice_scores
- [x] Tests for all remote function features (4 API tests, 4 Eval tests)

### Phase 7: Examples - ✅ COMPLETE (examples at root level)

**Note**: Examples exist at root level and in subdirectories, not in dedicated openai/otel/evals subdirs

#### Root Level Examples ✅
- [x] openai.rb - OpenAI tracing with chat completions ✅
- [x] trace.rb - Manual span creation and tracing ✅
- [x] eval.rb - Evaluations with test cases and scorers ✅
- [x] login.rb - Authentication examples ✅

#### Subdirectory Examples ✅
- [x] api/dataset.rb - Dataset API operations ✅
- [x] eval/dataset.rb - Evaluations using datasets ✅
- [x] eval/remote_functions.rb - Remote scoring functions ✅
- [x] internal/openai.rb - Comprehensive OpenAI features (vision, tools, streaming) ✅
- [x] internal/kitchen-sink.rb - Complex evaluation scenarios ✅
- [x] internal/evals-with-errors.rb - Error handling examples ✅

### Phase 8: Documentation & Polish - ⚠️ MOSTLY COMPLETE

#### Completed ✅
- [x] Write comprehensive README.md ✅ (2025-10-23)
  - Overview, installation, quick start sections
  - Three working examples (Evals, Tracing, OpenAI)
  - Features section, links to examples and API docs
  - Gem badge and beta status indicator
- [x] Update CONTRIBUTING.md ✅ (2025-10-23)
  - Development setup with mise and bundle
  - Testing guidelines (Minitest, plain assert)
  - Pull request workflow and troubleshooting
- [x] Run Standard linter and fix issues ✅
  - All code passing StandardRB linter
  - Rake tasks: lint, lint:fix
- [x] Set up CI/CD pipeline ✅ (2025-10-23)
  - GitHub Actions: ci.yml (tests + linter)
  - Publish workflows: publish-gem.yaml, publish-gem-prerelease.yaml
  - Release automation: rake release, release:publish, release:github, release:changelog

#### Incomplete ❌
- [ ] Document all public APIs (RDoc/YARD documentation) - IN PROGRESS
  - Some inline docs exist but not comprehensive
- [ ] Add inline code comments - PARTIAL
  - Core files have basic comments, needs expansion
- [x] ~~CHANGELOG.md~~ - NOT NEEDED (project decision, automated via GitHub releases)
- [ ] Verify 80%+ test coverage - ❌ ONLY 25%
  - Current coverage: 25.03% (202/807 lines)
  - Need significant increase to reach 80% target
  - Many files have low/no coverage (API client, some eval features)
- [ ] Tag v0.1.0 release - ❌ PENDING
  - Still at v0.0.1 in lib/braintrust/version.rb
  - No git tags exist yet
  - Waiting on coverage and CHANGELOG completion

## Current Status

**Last Updated**: 2025-10-23 (Session 10 - Documentation & Planning Review)
**Current Phase**: Phase 8 - Documentation & Polish ⚠️ MOSTLY COMPLETE
**Test Status**: 115 test runs, 398 assertions, 0 failures, 0 errors, 0 skips - ✅ ALL PASSING
**Test Coverage**: 25% (202/807 lines) - ❌ BELOW 80% TARGET
**Linter Status**: ✅ StandardRB passing, all files clean
**Version**: v0.0.1 (pre-release, not yet published to RubyGems)

**Completed Features**:
- ✅ Core SDK (init, config, state, login with retry)
- ✅ Tracing (OpenTelemetry integration, span processors, permalinks)
- ✅ OpenAI Integration (vision, tools, streaming, advanced metrics)
- ✅ Evaluations (cases, scorers, datasets, remote functions)
- ✅ API Client (datasets, functions)
- ✅ Documentation (README, CONTRIBUTING, examples)
- ✅ CI/CD (GitHub Actions, release automation)

**Remaining Work for v0.1.0**:
- ❌ Implement span filtering logic (AI spans filter)
- ❌ Increase test coverage from 25% to 80%+ target
- ❌ Comprehensive API documentation (RDoc/YARD)
- ❌ Tag and publish v0.1.0 release

## Deferred Items

- API::Projects (move from Internal::Experiments)
- API::Experiments (move from Internal::Experiments)
- Implement Parallelism (Eval.run parallelism parameter)
- OpenAI Responses API (`/v1/responses` endpoint - newer API, lower priority)
- OpenAI Additional Endpoints (embeddings, assistants, fine-tuning, images)
