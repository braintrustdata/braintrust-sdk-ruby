# Publishing the Ruby SDK

The `braintrust` gem is published from GitHub Actions via the **Release Ruby SDK** workflow
([`.github/workflows/release.yml`](.github/workflows/release.yml)), which is generated from the
canonical Ruby release template in
[`braintrustdata/sdk-actions`](https://github.com/braintrustdata/sdk-actions) (pinned by commit SHA).
Do not publish from your local machine.

The workflow is triggered manually (`workflow_dispatch`) and requires an explicit commit SHA. It
**reads the version from `lib/braintrust/version.rb` at that SHA** — the version cannot be overridden
from the workflow inputs, so a version bump must already be committed at the SHA you release. The
same workflow covers standard releases, backports, hotfixes, and release candidates.

## Bumping the version

Bump `lib/braintrust/version.rb` with the provided Rake tasks:

```bash
rake version:bump:patch   # or :minor, :major
```

## Stable release

1. Open a PR that bumps `lib/braintrust/version.rb` to the target version and merge it to `main`.
2. Copy the SHA of the version-bump **merge commit** on `main`.
3. Run the **Release Ruby SDK** workflow
   (Actions → Release Ruby SDK → Run workflow) with:
   - **Commit SHA** — the merge commit SHA from step 2.
   - **Dry run** — leave unchecked for a real release.
4. Approve the `rubygems-publish` environment if prompted.

The workflow validates the release, generates release notes, posts a pending notice to Slack, then
publishes the gem to RubyGems via trusted publishing (OIDC — no long-lived tokens), tags the commit,
and creates the GitHub Release.

## Pre-release (release candidate / alpha)

Release candidates use the same workflow; just release from a pre-release version on a branch.

1. Create a pre-release branch and commit `lib/braintrust/version.rb` set to the desired pre-release
   version (e.g. `0.1.0.alpha2`). Copy the SHA of that commit.
2. Run the **Release Ruby SDK** workflow with:
   - **Commit SHA** — the version-bump commit on your pre-release branch.
   - **Tag or SHA of previous release** — *(optional)* the version-bump SHA of the previous
     pre-release. Set this when you want the release notes to diff against, say, `alpha1` only rather than against the last stable release.
   - **Dry run** — leave unchecked for a real pre-release.

## Dry run

Check **Dry run** to exercise the workflow (build only) without tagging or publishing. It runs in the
`rubygems-publish-dry-run` environment and ships nothing.

## Verify

Spot-check that the release and changelog look right:

- https://rubygems.org/gems/braintrust
- https://github.com/braintrustdata/braintrust-sdk-ruby/releases

Then run the test app with the newly published gem:

- https://github.com/braintrustdata/sdk-test-apps — `make verify-ruby`
