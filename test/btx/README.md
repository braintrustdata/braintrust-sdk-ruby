# BTX — cross-language LLM-span spec tests

This suite validates the Ruby SDK's LLM instrumentation against the shared YAML
specs in [`braintrustdata/braintrust-spec`](https://github.com/braintrustdata/braintrust-spec),
the same specs used by every other Braintrust SDK.

For each spec file it:

1. Fetches the spec at the pinned ref (`spec-ref.txt`) into `.spec-cache/` (gitignored).
2. Executes the spec in-process: real provider API calls (OpenAI, Anthropic)
   wrapped with Braintrust instrumentation, captured via an in-memory OTel
   exporter, under a single parent span.
3. Validates the resulting brainstore spans against `expected_brainstore_spans`.

## Running

The suite needs the provider gems, so run it under the `contrib` appraisal:

```bash
# Replay from committed cassettes (no API keys, no network) — how CI runs:
bundle exec appraisal contrib rake test:btx

# Record cassettes (real API calls; requires OPENAI_API_KEY / ANTHROPIC_API_KEY):
VCR_MODE=all bundle exec appraisal contrib rake test:btx

# Live mode: real calls, flush to Braintrust, validate via BTQL
# (requires BRAINTRUST_API_KEY and a project):
VCR_OFF=true bundle exec appraisal contrib rake test:btx
```

Run a single spec:

```bash
bundle exec appraisal contrib ruby -Ilib:test \
  -e "require_relative 'test/btx/btx_test.rb'" -- --name=test_openai_completions
```

## Layout

| File | Responsibility |
|---|---|
| `spec-ref.txt` | Pinned `braintrust-spec` ref to fetch |
| `spec_fetcher.rb` | Download + cache the spec tarball (pure Ruby) |
| `spec_loader.rb` | Parse spec YAML, including the `!fn` / `!starts_with` / `!or` / `!gen` tags |
| `spec_executor.rb` | Make provider API calls under a Braintrust span; capture OTel spans |
| `span_converter.rb` | Convert in-memory OTel spans → brainstore format (incl. attachment refs) |
| `span_fetcher.rb` | Live-mode BTQL fetch with retry |
| `span_validator.rb` | Recursive matcher against `expected_brainstore_spans` |
| `btx_test.rb` | Minitest runner — one test per spec |

## Modes

| Mode | Trigger | Behaviour |
|---|---|---|
| replay (default) | committed cassettes | Replay HTTP; convert in-memory spans; no keys/network |
| record | `VCR_MODE=all` | Real API calls; write cassettes; validate in-memory |
| live | `VCR_OFF=true` | Real API calls; flush to Braintrust; validate via BTQL |

Cassettes live in `test/fixtures/vcr_cassettes/btx/<provider>/<spec>.yml` and are
scrubbed of API keys by the shared VCR config in `test/test_helper.rb`.

## Coverage / known gaps

Pinned spec ref: see `spec-ref.txt` (currently `v0.0.7`).

- Providers covered: `openai` (completions, streaming, tools, reasoning,
  attachments) and `anthropic` (messages, streaming, attachments,
  prompt_caching_5m, prompt_caching_1h).
- `bedrock` and `google` specs are **skipped at runtime** with a clear reason —
  the Ruby SDK has no instrumentation for them. The set of instrumentable
  `[provider, endpoint]` pairs lives in `SpecExecutor::SUPPORTED_ENDPOINTS`; add
  to it (plus a `dispatch` branch) when a new integration lands.

Notes:

- The `anthropic/prompt_caching_*` specs interpolate a `!gen vcr_nonce` cache
  buster. The nonce is **random in live mode** (to force a provider-side cache
  miss so creation metrics are non-zero) and **deterministic in record/replay**
  (so the request body matches the committed cassette).
- The `anthropic-beta` header for the 1h TTL variant is passed through via the
  spec's top-level `headers`.
