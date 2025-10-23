#!/usr/bin/env bash
# Script to validate a release tag for the Ruby SDK
# Ensures the tag matches the version in version.rb and is on the main branch

set -euo pipefail

# Get the repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Get the current tag (should be set in CI environment)
RELEASE_TAG="${GITHUB_REF_NAME:-}"

if [ -z "$RELEASE_TAG" ]; then
  echo "Error: GITHUB_REF_NAME is not set"
  echo "This script should be run in a GitHub Actions environment"
  exit 1
fi

echo "Validating release tag: $RELEASE_TAG"

# Extract version from tag (remove 'v' prefix)
TAG_VERSION="${RELEASE_TAG#v}"

# Get version from version.rb
VERSION=$(ruby -r "./lib/braintrust/version.rb" -e "puts Braintrust::VERSION")

echo "Tag version:    $TAG_VERSION"
echo "version.rb:     $VERSION"

# Validate version matches
if [ "$TAG_VERSION" != "$VERSION" ]; then
  echo ""
  echo "Error: Tag version does not match version.rb"
  echo "  Tag:        $TAG_VERSION"
  echo "  version.rb: $VERSION"
  exit 1
fi

echo "✓ Version matches"

# Validate the tag is on the main branch
MAIN_BRANCH="main"
TAG_COMMIT=$(git rev-parse "$RELEASE_TAG")
MAIN_COMMIT=$(git rev-parse "origin/$MAIN_BRANCH")

# Check if the tag commit is an ancestor of main or is main
if ! git merge-base --is-ancestor "$TAG_COMMIT" "$MAIN_COMMIT" && [ "$TAG_COMMIT" != "$MAIN_COMMIT" ]; then
  echo ""
  echo "Error: Tag $RELEASE_TAG is not on the $MAIN_BRANCH branch"
  echo "  Tag commit:  $TAG_COMMIT"
  echo "  Main commit: $MAIN_COMMIT"
  exit 1
fi

echo "✓ Tag is on the $MAIN_BRANCH branch"

echo ""
echo "✓ Release tag validation successful"
echo "  Tag:     $RELEASE_TAG"
echo "  Version: $VERSION"
echo "  Commit:  $TAG_COMMIT"
