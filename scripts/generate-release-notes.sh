#!/usr/bin/env bash
# Script to generate release notes for GitHub Release
# Shows commits since the previous release
# Expected tag format: v0.0.1, v0.0.2, etc. (with 'v' prefix)

set -euo pipefail

# Get the repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Get current tag (expects format: v0.0.1)
# Accepts optional argument: ./generate-release-notes.sh v0.0.2
# Defaults to HEAD (unreleased changes) for local development
CURRENT_TAG="${1:-${GITHUB_REF_NAME:-$(git describe --tags --exact-match 2>/dev/null || echo "HEAD")}}"

# Special case: HEAD shows what would be in next release
if [ "$CURRENT_TAG" = "HEAD" ]; then
  PREVIOUS_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  if [ -z "$PREVIOUS_TAG" ]; then
    echo "Error: No previous tag found"
    exit 1
  fi

  echo "## Changelog"
  echo ""
  git log "${PREVIOUS_TAG}..HEAD" --pretty=format:"- %s (%h)" --no-merges
  exit 0
fi

# Validate tag format (must start with 'v' and contain version number)
if [[ ! "$CURRENT_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "Error: Invalid tag format. Expected format: v0.0.1"
  echo "Got: $CURRENT_TAG"
  exit 1
fi

# Get previous tag
PREVIOUS_TAG=$(git describe --tags --abbrev=0 "${CURRENT_TAG}^" 2>/dev/null || echo "")

# Generate release notes with consistent header
echo "## Changelog"
echo ""

if [ -n "$PREVIOUS_TAG" ]; then
  git log "${PREVIOUS_TAG}..${CURRENT_TAG}" --pretty=format:"- %s (%h)" --no-merges
else
  echo "Initial beta version of the Ruby SDK."
fi
