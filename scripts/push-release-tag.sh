#!/usr/bin/env bash
# Script to push a release tag for the Ruby SDK
# Inspired by py/scripts/push-release-tag.sh

set -euo pipefail

# Parse arguments
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--dry-run]"
      exit 1
      ;;
  esac
done

# Get the repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Fetch latest tags
echo "Fetching latest tags..."
git fetch --tags

# Get version from version.rb
VERSION=$(ruby -r "./lib/braintrust/version.rb" -e "puts Braintrust::VERSION")
TAG="v${VERSION}"

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Error: Tag $TAG already exists"
  exit 1
fi

# Get current commit info
COMMIT_SHA=$(git rev-parse HEAD)
COMMIT_SHORT_SHA=$(git rev-parse --short HEAD)
REPO_URL=$(git config --get remote.origin.url | sed 's/\.git$//' | sed 's/git@github.com:/https:\/\/github.com\//')

# Get the previous tag for comparison
PREVIOUS_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

echo ""
echo "========================================"
echo "Release Information"
echo "========================================"
echo "New version tag: $TAG"
echo "Current commit:  $COMMIT_SHA"
echo "Commit URL:      ${REPO_URL}/commit/${COMMIT_SHA}"
if [ -n "$PREVIOUS_TAG" ]; then
  echo "Previous tag:    $PREVIOUS_TAG"
  echo "Changelog:       ${REPO_URL}/compare/${PREVIOUS_TAG}...${COMMIT_SHORT_SHA}"
fi
echo "========================================"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: Would create and push tag $TAG"
  echo "Exiting without making changes."
  exit 0
fi

# Require confirmation
echo "This will create and push tag $TAG to trigger the production release."
echo "Type 'YOLO' to confirm:"
read -r CONFIRMATION

if [ "$CONFIRMATION" != "YOLO" ]; then
  echo "Confirmation failed. Aborting."
  exit 1
fi

# Create and push the tag
echo ""
echo "Creating tag $TAG..."
git tag "$TAG"

echo "Pushing tag $TAG..."
git push origin "$TAG"

echo ""
echo "✓ Tag $TAG has been pushed successfully!"
echo ""
echo "Monitor the release workflow at:"
echo "${REPO_URL}/actions"
