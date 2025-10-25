#!/usr/bin/env bash
# Script to generate release notes for GitHub Release
# Shows commits between two points in history
# Expected tag format: v0.0.1, v0.0.2, etc. (with 'v' prefix)

set -euo pipefail

# Get the repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Determine END commit (what to release)
# Priority: arg > GITHUB_REF_NAME > current tag > HEAD
END="${1:-${GITHUB_REF_NAME:-$(git describe --tags --exact-match 2>/dev/null || echo "HEAD")}}"

# Validate tag format if not HEAD
if [ "$END" != "HEAD" ] && [[ ! "$END" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "Error: Invalid tag format. Expected format: v0.0.1 or HEAD"
  echo "Got: $END"
  exit 1
fi

# Determine START commit (previous release)
if [ "$END" = "HEAD" ]; then
  # Local: show unreleased changes since last tag
  START=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
else
  # CI: show changes since previous tag
  START=$(git describe --tags --abbrev=0 "${END}^" 2>/dev/null || echo "")
fi

# Generate changelog
echo "## Changelog"
echo ""

if [ -n "$START" ]; then
  git log "${START}..${END}" --pretty=format:"- %s (%h)" --no-merges
else
  echo "Initial beta version of the Ruby SDK."
fi
