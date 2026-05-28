#!/usr/bin/env bash
# Sanity-checks that GITHUB_REF_NAME is set and matches version.rb.
# Called internally by rake release via rake release:validate.
# The release workflow handles all meaningful pre-release checks
# (tag existence, explicit SHA targeting) before this script runs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RELEASE_TAG="${GITHUB_REF_NAME:-}"

if [ -z "$RELEASE_TAG" ]; then
  echo "Error: GITHUB_REF_NAME is not set"
  exit 1
fi

TAG_VERSION="${RELEASE_TAG#v}"
VERSION=$(ruby -r "./lib/braintrust/version.rb" -e "puts Braintrust::VERSION")

if [ "$TAG_VERSION" != "$VERSION" ]; then
  echo "Error: Tag version ($TAG_VERSION) does not match version.rb ($VERSION)"
  exit 1
fi

echo "✓ Tag $RELEASE_TAG matches version.rb ($VERSION)"
