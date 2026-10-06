# Export middleware: notes for adopting this branch

Branch `feature/span-export-middleware` replaces stacked `prepend` modules on our exporters with a single middleware chain around `export`. It is parked on purpose: span customizers (PR #217, SDK-316) shipped with the simpler prepend design, and this branch is waiting for a PR that needs it. Delete this file when the branch is integrated.

## Why it exists

Before this branch, each exporter behavior was its own prepended module, and order was the reverse of the `prepend` lines:

```ruby
prepend SpanCustomization   # runs second
prepend SpanOrigin          # runs first
```

That made order implicit, and stateful behaviors (customizers) had to smuggle config through the exporter's constructor. The chain makes order explicit and lets each middleware own its state.

## Design at a glance

```
SpanExporter#export(spans)              (ExportMiddleware, prepended once)
  └─ middleware.invoke(spans) { |spans| super }
       ├─ SpanOrigin          class default: yield(enrich(spans))
       ├─ SpanCustomizers     per instance: yield(customize(spans)), or return FAILURE
       └─ block → super → main's grouping by braintrust.parent → OTLP send
```

| Piece | Where | Role |
|---|---|---|
| `ExportMiddleware` | `lib/braintrust/trace/export_middleware.rb` | Prepended once per exporter class. Wraps `export` with the chain; `super` is the terminal |
| `ExportMiddleware::Chain` | same file | Ordered entries, one per class: `add`, `remove`, `exists?`, `insert_before`, `insert_after`, `clear`, `entries`, `invoke` |
| Middleware contract | any object | `call(spans)` that yields spans to continue, or returns an export result (`SUCCESS`/`FAILURE`) to halt. Code after `yield` sees the downstream result |
| `SpanOrigin` | `span_origin.rb` | Stateless middleware via `SpanOrigin.call` |
| `SpanCustomizers` | `span_customizers.rb` | Stateful middleware via `#call`; fail-closed on hook errors |
| Wiring | `span_exporter.rb`, `test/support/in_memory_exporter.rb`, `trace.rb` | Classes declare defaults (`middleware.add(SpanOrigin)`); `Trace.enable` adds `SpanCustomizers` to the instance |

Chain semantics (all covered in `test/braintrust/trace/export_middleware_test.rb`):

- Instances start from a copy of their class's chain; subclasses (e.g. `RecordingExporter` in tests) from a copy of their parent's.
- Adding to one instance never affects other instances or the class.
- An instance chain freezes on its first `export`; configure before handing the exporter to a span processor.
- Entries are keyed by exact class (or by the module itself for stateless middleware like `SpanOrigin`). `add` replaces an existing entry of the same class, so swapping is one call: `exporter.middleware.add(SpanCustomizers.new(other))`.
- `insert_before`/`insert_after` raise `ArgumentError` if the anchor is missing (Sidekiq silently inserts at the front).

Pattern: inspired by Sidekiq's middleware chain, not a copy of it.

| | Sidekiq | This branch |
|---|---|---|
| Traversal | Recursive, ends in a block | Same |
| Registration | `add(klass, *args)`, new instance per job | `add(instance)`, built once, so customizers validate at registration |
| `yield` passes | Nothing (job hash mutated in place) | Transformed spans |
| API | `add`, `remove`, `prepend`, `insert_before`, `insert_after`, `exists?`, `clear`, `entries` | Same minus `prepend` (confusable with `Module#prepend`) |

Rack style (each middleware wraps an app at build time) was rejected because the terminal (`super`) only exists inside the prepended `export` call, so it must be supplied per call as a block.

## Behavior changes vs. the base commit

- `SpanExporter.new` no longer takes `span_customizers:`; callers add `SpanCustomizers.new(list)` to `exporter.middleware`. `Trace.enable` does this for users, so `Braintrust.init(span_customizers: ...)` is unchanged.
- `Braintrust.init(exporter:, span_customizers:)` now works for any exporter that prepends `ExportMiddleware` (e.g. `Test::Support::InMemoryExporter`). Exporters without it still raise `ArgumentError`.
- `SpanOrigin` is no longer prependable (`SpanOrigin#export` removed); use it as middleware.
- `SpanCustomization` module deleted.

## Integrating into another PR

1. Rebase onto the target branch. Expect conflicts in `span_exporter.rb`, `span_customizers.rb`, `span_origin.rb`, `trace.rb` and `test/support/in_memory_exporter.rb` if span customizer code has moved on.
2. If the target implements spec PR braintrust-spec#64 (strip failing spans and tag `customizer-error` instead of failing the batch), `SpanCustomizers#call` simply stops halting: it always yields. The chain itself does not change.
3. New exporter behaviors (sampling, metrics/timing, attachment handling) should be middleware objects added with `middleware.add`, not new prepended modules.
4. Run `rake test`, `rake lint`, and `bundle exec appraisal opentelemetry-min rake test` / `opentelemetry-latest`.

## Open questions and risks

- `middleware` is a public method on our exporters (marked `@api private`). Decide whether to keep it internal or document it as a supported extension point.
- The chain adds one object and one block per middleware per export; negligible next to OTLP encoding, but unmeasured.

## References

- [PR #217: span customizers (SDK-316)](https://github.com/braintrustdata/braintrust-sdk-ruby/pull/217)
- [Span customizer spec](https://github.com/braintrustdata/braintrust-spec/blob/main/skills/instrumentation-spec/references/features/span-customizers.md)
- [Spec PR #64: span customizer error handling](https://github.com/braintrustdata/braintrust-spec/pull/64)
- [Sidekiq middleware](https://github.com/sidekiq/sidekiq/wiki/Middleware)
