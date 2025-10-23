#!/usr/bin/env bash
# Script to generate release notes for GitHub Release
# Compares current tag with previous tag

set -euo pipefail

# Get the repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Get current tag
CURRENT_TAG="${GITHUB_REF_NAME:-$(git describe --tags --exact-match 2>/dev/null || echo "")}"

if [ -z "$CURRENT_TAG" ]; then
  echo "Error: No tag found. This script should be run on a tagged commit."
  exit 1
fi

# Get previous tag
PREVIOUS_TAG=$(git describe --tags --abbrev=0 "${CURRENT_TAG}^" 2>/dev/null || echo "")

# Generate release notes
if [ -n "$PREVIOUS_TAG" ]; then
  echo "## Changes since $PREVIOUS_TAG"
  echo ""
  git log "${PREVIOUS_TAG}..${CURRENT_TAG}" --pretty=format:"- %s (%h)" --no-merges
else
  echo "## Initial Release"
  echo ""
  echo "First release of the Braintrust Ruby SDK"
fi
