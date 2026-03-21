#!/bin/bash
set -e

# SlothyTerminal Full Release Script
# Builds, signs, notarizes, updates appcast, creates GitHub release, uploads DMG.
#
# Usage: ./scripts/release.sh VERSION
# Example: ./scripts/release.sh 2026.2.15
#
# Prerequisites:
#   - .env file with Apple credentials (APPLE_ID, APP_SPECIFIC_PASSWORD, TEAM_ID)
#   - sparkle-tools/bin/sign_update (Sparkle EdDSA signing tool)
#   - gh CLI authenticated (brew install gh && gh auth login)
#   - appcast.xml entry for VERSION already exists with SIGNATURE_HERE / FILE_SIZE_IN_BYTES placeholders
#   - CHANGELOG.md entry for VERSION already exists

VERSION="${1}"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 VERSION"
  echo "Example: $0 2026.2.15"
  exit 1
fi

APP_NAME="SlothyTerminal"
BUILD_DIR="./build"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
SPARKLE_BIN="./sparkle-tools/bin/sign_update"
PBXPROJ="SlothyTerminal.xcodeproj/project.pbxproj"
TAG="v$VERSION"

echo "==========================================="
echo "  $APP_NAME Full Release"
echo "  Version: $VERSION"
echo "  Tag: $TAG"
echo "==========================================="

# ── Preflight checks ──────────────────────────────────────────────

echo ""
echo "[preflight] Checking prerequisites..."

if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI not found. Install with: brew install gh"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "ERROR: gh CLI not authenticated. Run: gh auth login"
  exit 1
fi

if [ ! -f "$SPARKLE_BIN" ]; then
  echo "ERROR: Sparkle sign_update not found at $SPARKLE_BIN"
  echo "Download from: https://github.com/sparkle-project/Sparkle/releases/latest"
  exit 1
fi

if [ ! -f "scripts/build-release.sh" ]; then
  echo "ERROR: scripts/build-release.sh not found"
  exit 1
fi

if ! grep -q "SIGNATURE_HERE" appcast.xml; then
  echo "ERROR: appcast.xml does not contain SIGNATURE_HERE placeholder for this release."
  echo "Add the appcast entry with placeholders before running this script."
  exit 1
fi

if ! grep -q "\[$VERSION\]" CHANGELOG.md; then
  echo "ERROR: CHANGELOG.md does not contain an entry for [$VERSION]."
  echo "Write the changelog entry before running this script."
  exit 1
fi

echo "All preflight checks passed."

# ── Step 1: Build, sign, notarize ─────────────────────────────────

echo ""
echo "==========================================="
echo "  Step 1: Build & Notarize"
echo "==========================================="
echo ""

./scripts/build-release.sh "$VERSION"

if [ ! -f "$DMG_PATH" ]; then
  echo "ERROR: DMG not found at $DMG_PATH after build"
  exit 1
fi

# ── Step 2: Sparkle signature ─────────────────────────────────────

echo ""
echo "==========================================="
echo "  Step 2: Sparkle Signing"
echo "==========================================="
echo ""

SPARKLE_OUTPUT=$($SPARKLE_BIN "$DMG_PATH")
SIGNATURE=$(echo "$SPARKLE_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
DMG_SIZE_BYTES=$(stat -f%z "$DMG_PATH")

if [ -z "$SIGNATURE" ]; then
  echo "ERROR: Failed to extract Sparkle EdDSA signature"
  echo "sign_update output: $SPARKLE_OUTPUT"
  exit 1
fi

echo "Signature: $SIGNATURE"
echo "File size: $DMG_SIZE_BYTES bytes"

# ── Step 3: Update appcast.xml ────────────────────────────────────

echo ""
echo "==========================================="
echo "  Step 3: Update appcast.xml"
echo "==========================================="
echo ""

sed -i '' "s|sparkle:edSignature=\"SIGNATURE_HERE\"|sparkle:edSignature=\"$SIGNATURE\"|" appcast.xml
sed -i '' "s|length=\"FILE_SIZE_IN_BYTES\"|length=\"$DMG_SIZE_BYTES\"|" appcast.xml

echo "Updated appcast.xml with signature and file size."

# Verify the placeholders were replaced.
if grep -q "SIGNATURE_HERE" appcast.xml || grep -q "FILE_SIZE_IN_BYTES" appcast.xml; then
  echo "ERROR: appcast.xml still contains placeholder values after update"
  exit 1
fi

# ── Step 4: Bump build number in Xcode project ───────────────────

echo ""
echo "==========================================="
echo "  Step 4: Bump Build Number"
echo "==========================================="
echo ""

## Extract the build number from the appcast entry for this version.
BUILD_NUMBER=$(grep -B1 "shortVersionString>$VERSION<" appcast.xml | grep "sparkle:version" | sed 's/.*>\([0-9]*\)<.*/\1/')

if [ -n "$BUILD_NUMBER" ]; then
  CURRENT_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PBXPROJ" | sed 's/.*= \([0-9]*\);/\1/')

  if [ "$CURRENT_BUILD" != "$BUILD_NUMBER" ]; then
    sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PBXPROJ"
    echo "Bumped CURRENT_PROJECT_VERSION: $CURRENT_BUILD → $BUILD_NUMBER"
  else
    echo "CURRENT_PROJECT_VERSION already set to $BUILD_NUMBER"
  fi
else
  echo "WARNING: Could not extract build number from appcast.xml, skipping pbxproj update"
fi

# ── Step 5: Extract release notes from CHANGELOG.md ──────────────

echo ""
echo "==========================================="
echo "  Step 5: Extract Release Notes"
echo "==========================================="
echo ""

## Extract the section for this version (between ## [VERSION] and the next ## [).
RELEASE_NOTES=$(awk "/^## \[$VERSION\]/{found=1; next} /^## \[/{if(found) exit} found{print}" CHANGELOG.md)

if [ -z "$RELEASE_NOTES" ]; then
  echo "WARNING: Could not extract release notes from CHANGELOG.md"
  RELEASE_NOTES="Release $VERSION"
fi

echo "$RELEASE_NOTES"

# ── Step 6: Commit changes ────────────────────────────────────────

echo ""
echo "==========================================="
echo "  Step 6: Commit Release Files"
echo "==========================================="
echo ""

git add appcast.xml
git add "$PBXPROJ"

if git diff --cached --quiet; then
  echo "No changes to commit (files already up to date)."
else
  git commit -m "chore: release $VERSION

Update appcast.xml with Sparkle signature and file size.
Bump CURRENT_PROJECT_VERSION to $BUILD_NUMBER."

  echo "Committed release changes."
fi

# ── Step 7: Create GitHub release & upload DMG ────────────────────

echo ""
echo "==========================================="
echo "  Step 7: GitHub Release"
echo "==========================================="
echo ""

## Check if release already exists.
if gh release view "$TAG" &>/dev/null; then
  echo "Release $TAG already exists. Uploading DMG to existing release..."
  gh release upload "$TAG" "$DMG_PATH" --clobber
else
  echo "Creating release $TAG..."
  gh release create "$TAG" \
    "$DMG_PATH" \
    --title "SlothyTerminal $VERSION" \
    --notes "$RELEASE_NOTES"
fi

RELEASE_URL=$(gh release view "$TAG" --json url -q '.url')
echo ""
echo "Release published: $RELEASE_URL"

# ── Step 8: Push ──────────────────────────────────────────────────

echo ""
echo "==========================================="
echo "  Step 8: Push"
echo "==========================================="
echo ""

BRANCH=$(git branch --show-current)
echo "Current branch: $BRANCH"
read -p "Push to origin/$BRANCH? [y/N] " PUSH_CONFIRM

if [[ "$PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
  git push origin "$BRANCH"
  echo "Pushed to origin/$BRANCH"
else
  echo "Skipped push. Run manually: git push origin $BRANCH"
fi

# ── Done ──────────────────────────────────────────────────────────

echo ""
echo "==========================================="
echo "  Release Complete!"
echo "==========================================="
echo ""
echo "  Version: $VERSION"
echo "  Tag: $TAG"
echo "  DMG: $DMG_PATH"
echo "  Release: $RELEASE_URL"
echo ""
echo "  Sparkle auto-update will pick up the new version"
echo "  once appcast.xml is on the main branch."
echo ""
