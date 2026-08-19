# Publishing the Ruby SDK

The `braintrust` gem is published from GitHub Actions via the **Release Ruby SDK** workflow ([`.github/workflows/release.yml`](.github/workflows/release.yml)). Do not publish from your local machine — there are no local publish or tag Rake tasks, and RubyGems accepts pushes only from this workflow.

The workflow is triggered manually (`workflow_dispatch`) and requires an explicit commit SHA. It **reads the version from `lib/braintrust/version.rb` at that SHA** — the version cannot be overridden from the workflow inputs, so a version bump must already be committed at the SHA you release. The same workflow covers standard releases, backports, hotfixes, and release candidates.

## Bumping the version

Bump `lib/braintrust/version.rb` with the provided Rake tasks:

```bash
rake version:bump:patch   # or :minor, :major
```

## Stable release

1. Open a PR that bumps `lib/braintrust/version.rb` to the target version and merge it to `main`.
2. Copy the SHA of the version-bump **merge commit** on `main`.
3. Run the **Release Ruby SDK** workflow (Actions → Release Ruby SDK → Run workflow) with:
   - **Release type** — `stable`.
   - **Commit SHA** — the merge commit SHA from step 2.
   - **Dry run** — leave unchecked for a real release.
4. Approve the `publish` environment when prompted.

The workflow validates the release, generates release notes, posts a pending notice to Slack, then publishes the gem to RubyGems via trusted publishing (OIDC — no long-lived tokens), tags the commit, and creates the GitHub Release with a signed SBOM attached.

## Pre-release (release candidate / alpha)

Release candidates use the same workflow; just release from a pre-release version on a branch.

1. Create a pre-release branch and commit `lib/braintrust/version.rb` set to the desired pre-release version (e.g. `0.1.0.alpha2`). Copy the SHA of that commit.
2. Run the **Release Ruby SDK** workflow with:
   - **Release type** — `prerelease`.
   - **Commit SHA** — the version-bump commit on your pre-release branch.
   - **Release-notes anchor** — *(optional)* the tag or version-bump SHA of the previous pre-release. Set this when you want the release notes to diff against, say, `alpha1` only rather than against the last stable release. Leave it empty to diff against the previous tag. Note that a full SHA (rather than a tag) yields empty notes.
   - **Dry run** — leave unchecked for a real pre-release.

> **`prerelease` publishes the gem but does not tag the commit or create a GitHub Release.** Choose `stable` if you want either of those.

Releasing from a branch other than `main` produces a warning, not a failure.

## Dry run

Check **Dry run** to exercise the workflow (build only) without tagging or publishing. It runs in the `publish-dry-run` environment and ships nothing.

## Verify

Spot-check that the release and changelog look right:

- https://rubygems.org/gems/braintrust
- https://github.com/braintrustdata/braintrust-sdk-ruby/releases

Confirm the published gem carries its SBOM and build provenance:

```bash
gh attestation verify braintrust-<version>.gem --repo braintrustdata/braintrust-sdk-ruby
```

Then run the test app with the newly published gem:

- https://github.com/braintrustdata/sdk-test-apps — `make verify-ruby`

---

## Maintenance

`release.yml` is **generated** from the `release/ruby/turnkey` template in [`braintrustdata/sdk-actions`](https://github.com/braintrustdata/sdk-actions), which supplies the release actions as SHA-pinned building blocks. Do not hand-edit it to pick up upstream changes; use the generator.

### Updating to a newer sdk-actions

From an `sdk-actions` checkout:

```bash
WF=/path/to/braintrust-sdk-ruby/.github/workflows/release.yml
REF=$(git rev-parse origin/main)                  # resolve it: --ref origin/main is not expanded
ruby bin/workflow compare  --ref "$REF" "$WF"     # preview the upstream delta
ruby bin/workflow update   --ref "$REF" "$WF"     # apply it, keeping local edits
ruby bin/workflow validate "$WF"                  # schema-check
```

Pass `--ref` explicitly — `compare` defaults to the ref already recorded in the file, which shows local drift rather than upstream changes.

`update` 3-way merges the upstream delta and bumps the pinned ref. Then:

1. Read `git diff`. The four `uses:` pins are the only trace of changes *inside* the actions, so also skim upstream's log between the old and new ref for behavior changes; a major-version jump in the `version` field of the provenance header means breaking changes.
2. Run `bash scripts/ensure-pinned-actions.sh` (CI enforces this too).
3. Open a PR and verify with a **Dry run** before the next real release.

The `# sdk-actions: {...}` header on line 2 records the template, pinned ref, and generation parameters — `compare`/`update` need it, so keep it intact.

### Local edits

This repo carries two deliberate edits on top of the template. `compare` should report these and nothing else; if `update` drops one, re-apply it:

- the `_instructions` dispatch input (the merge-a-version-bump-PR warning)
- `slack_mention: '@sdk-eng'` on the `request-approval` job

### Required repository configuration

- GitHub Environments `publish` (required reviewers, prevent self-review) and `publish-dry-run`.
- A RubyGems trusted publisher for `braintrust`: repo `braintrustdata/braintrust-sdk-ruby`, workflow `release.yml`, environment `publish`. Renaming the workflow file or the environment requires updating this, or `gem push` fails with an OIDC error.
- Repo secret `SLACK_BOT_TOKEN` and variable `SLACK_SDK_RELEASE_CHANNEL` for notifications.
