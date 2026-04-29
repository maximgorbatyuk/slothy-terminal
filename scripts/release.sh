#!/bin/bash
set -e

# SlothyTerminal Full Release Script
# Builds, signs, notarizes, updates appcast, creates GitHub release, uploads DMG.
#
# Usage: ./scripts/release.sh [VERSION]
#   - If VERSION is omitted, bumps the last segment of MARKETING_VERSION
#     (e.g. 2026.3.1 → 2026.3.2).
#   - Any uncommitted working-tree changes are committed before the release
#     begins, with the message "Commit before release VERSION".
# Example: ./scripts/release.sh 2026.2.15
# Example: ./scripts/release.sh        # auto-bumps patch
#
# Prerequisites:
#   - .env file with Apple credentials (APPLE_ID, APP_SPECIFIC_PASSWORD, TEAM_ID)
#   - sparkle-tools/bin/sign_update (Sparkle EdDSA signing tool)
#   - gh CLI authenticated (brew install gh && gh auth login)
#   - appcast.xml entry for VERSION already exists with BUILD_NUMBER / SIGNATURE_HERE / FILE_SIZE_IN_BYTES placeholders
#   - CHANGELOG.md entry for VERSION already exists
#
# The script automatically:
#   - Bumps MARKETING_VERSION in the Xcode project to VERSION
#   - Increments CURRENT_PROJECT_VERSION (build number) by 1
#   - Replaces BUILD_NUMBER placeholder in appcast.xml with the new build number

VERSION="${1}"
PBXPROJ="SlothyTerminal.xcodeproj/project.pbxproj"

if [ -z "$VERSION" ]; then
  CURRENT_MARKETING=$(grep -m1 "MARKETING_VERSION" "$PBXPROJ" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')

  if [ -z "$CURRENT_MARKETING" ]; then
    echo "ERROR: Could not read MARKETING_VERSION from $PBXPROJ"
    exit 1
  fi

  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_MARKETING"

  if ! [[ "$MAJOR" =~ ^[0-9]+$ ]] || ! [[ "$MINOR" =~ ^[0-9]+$ ]] || ! [[ "$PATCH" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Current MARKETING_VERSION ('$CURRENT_MARKETING') does not match NNNN.N.N pattern."
    echo "Pass an explicit version: $0 VERSION"
    exit 1
  fi

  VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
  echo "No version argument — auto-deriving next patch: $CURRENT_MARKETING → $VERSION"
fi

APP_NAME="SlothyTerminal"
BUILD_DIR="./build"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
SPARKLE_BIN="./sparkle-tools/bin/sign_update"
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

## Check that appcast.xml has at least one real (non-template) entry with placeholders.
## The template comment always has these strings, so look outside the comment block.
APPCAST_ITEMS=$(awk '/^    <item>/,/<\/item>/' appcast.xml)

if ! echo "$APPCAST_ITEMS" | grep -q "SIGNATURE_HERE"; then
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

# ── Commit any pending changes before release ─────────────────────

echo ""
echo "==========================================="
echo "  Pre-release: Commit Pending Changes"
echo "==========================================="
echo ""

if [ -n "$(git status --porcelain)" ]; then
  echo "Uncommitted changes detected — staging and committing."
  git add -A
  git commit -m "Commit before release $VERSION"
  echo "Committed pending changes as: Commit before release $VERSION"
else
  echo "Working tree clean — nothing to commit."
fi

# ── Step 1: Bump Xcode project version ───────────────────────────

echo ""
echo "==========================================="
echo "  Step 1: Bump Xcode Project Version"
echo "==========================================="
echo ""

CURRENT_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PBXPROJ" | sed 's/.*= \([0-9]*\);/\1/')
NEW_BUILD=$((CURRENT_BUILD + 1))
CURRENT_MARKETING=$(grep -m1 "MARKETING_VERSION" "$PBXPROJ" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')

echo "MARKETING_VERSION: $CURRENT_MARKETING → $VERSION"
echo "CURRENT_PROJECT_VERSION: $CURRENT_BUILD → $NEW_BUILD"

sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

echo "Updated $PBXPROJ"

# ── Step 2: Build, sign, notarize ─────────────────────────────────

echo ""
echo "==========================================="
echo "  Step 2: Build & Notarize"
echo "==========================================="
echo ""

./scripts/build-release.sh "$VERSION"

if [ ! -f "$DMG_PATH" ]; then
  echo "ERROR: DMG not found at $DMG_PATH after build"
  exit 1
fi

# ── Step 3: Sparkle signature ─────────────────────────────────────

echo ""
echo "==========================================="
echo "  Step 3: Sparkle Signing"
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

# ── Step 4: Update appcast.xml ────────────────────────────────────

echo ""
echo "==========================================="
echo "  Step 4: Update appcast.xml"
echo "==========================================="
echo ""

## Replace placeholders only in the <item> block for this specific version.
## The template comment in appcast.xml also contains these strings — skip it.
## BUILD_NUMBER appears before shortVersionString, so buffer each <item> block.
awk -v sig="$SIGNATURE" -v size="$DMG_SIZE_BYTES" -v ver="$VERSION" -v build="$NEW_BUILD" '
  /<item>/ { in_item = 1; buf = "" }
  in_item {
    buf = buf $0 "\n"
  }
  in_item && /<\/item>/ {
    in_item = 0
    if (index(buf, ver)) {
      gsub(/BUILD_NUMBER/, build, buf)
      gsub(/SIGNATURE_HERE/, sig, buf)
      gsub(/FILE_SIZE_IN_BYTES/, size, buf)
    }
    printf "%s", buf
    next
  }
  !in_item { print }
' appcast.xml > appcast.xml.tmp && mv appcast.xml.tmp appcast.xml

echo "Updated appcast.xml with build number ($NEW_BUILD), signature, and file size."

## Verify: the real entry should have real values, template comment may still have placeholders.
VERSION_BLOCK=$(awk -v ver="$VERSION" '
  /shortVersionString>/ && index($0, ver) { in_ver = 1 }
  in_ver { print }
  in_ver && /<\/item>/ { exit }
' appcast.xml)

if echo "$VERSION_BLOCK" | grep -q "BUILD_NUMBER"; then
  echo "ERROR: appcast.xml entry for $VERSION still contains BUILD_NUMBER"
  exit 1
fi
if echo "$VERSION_BLOCK" | grep -q "SIGNATURE_HERE"; then
  echo "ERROR: appcast.xml entry for $VERSION still contains SIGNATURE_HERE"
  exit 1
fi
if echo "$VERSION_BLOCK" | grep -q "FILE_SIZE_IN_BYTES"; then
  echo "ERROR: appcast.xml entry for $VERSION still contains FILE_SIZE_IN_BYTES"
  exit 1
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

Bump MARKETING_VERSION to $VERSION, CURRENT_PROJECT_VERSION to $NEW_BUILD.
Update appcast.xml with build number, Sparkle signature, and file size."

  echo "Committed release changes."
fi

# ── Step 7: Push & merge to main ──────────────────────────────────
#
# NOTE: This must run BEFORE `gh release create` (Step 8). When `gh release
# create TAG` is invoked without `--target` and the tag doesn't exist yet,
# GitHub creates it against the latest state of the default branch (main)
# on the server. If we push/merge afterwards, the tag ends up pointing at
# the previous release's bump commit instead of the new one. Pushing first
# (and passing `--target main` below) makes the tag land on the right SHA.

echo ""
echo "==========================================="
echo "  Step 7: Push & Merge to Main"
echo "==========================================="
echo ""

BRANCH=$(git branch --show-current)
echo "Current branch: $BRANCH"

git push origin "$BRANCH"
echo "Pushed to origin/$BRANCH"

if [ "$BRANCH" != "main" ]; then
  echo ""
  echo "Merging $BRANCH into main..."
  git checkout main
  git pull origin main
  git merge "$BRANCH" --no-edit
  git push origin main
  echo "Merged and pushed to origin/main"

  ## Switch back to the original branch.
  git checkout "$BRANCH"
  echo "Switched back to $BRANCH"
fi

# ── Step 8: Create GitHub release & upload DMG ────────────────────

echo ""
echo "==========================================="
echo "  Step 8: GitHub Release"
echo "==========================================="
echo ""

## Check if release already exists.
if gh release view "$TAG" &>/dev/null; then
  echo "Release $TAG already exists. Uploading DMG to existing release..."
  gh release upload "$TAG" "$DMG_PATH" --clobber
else
  echo "Creating release $TAG (tagging origin/main HEAD)..."
  gh release create "$TAG" \
    "$DMG_PATH" \
    --target main \
    --title "SlothyTerminal $VERSION" \
    --notes "$RELEASE_NOTES"
fi

RELEASE_URL=$(gh release view "$TAG" --json url -q '.url')
echo ""
echo "Release published: $RELEASE_URL"

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
echo "  Sparkle auto-update is now live (appcast.xml on main)."
echo ""
