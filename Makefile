#!/bin/bash
set -e

# Create a new release: builds the app, tags it, and pushes everything.
# Usage: make release [vX.Y.Z]

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: make release [vX.Y.Z]"
  echo "  e.g. make release v0.2.0"
  exit 1
fi

# Ensure main is up to date
git switch main
git pull origin main

# Build the app
chmod +x build.sh
./build.sh

# Tag and push
git tag "$VERSION"
git push origin main "$VERSION"

echo ""
echo "✅ Tagged $VERSION and pushed to origin."
echo "GitHub Actions will build and upload the release automatically."
echo ""
echo "To create the release on GitHub with notes:"
echo "  gh release create $VERSION --generate-notes --draft"