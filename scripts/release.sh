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

## Refuse to overwrite an already-published release. If you really want to
## re-upload the DMG to an existing release, do it explicitly with
## `gh release upload v$VERSION <dmg> --clobber` outside this script.
if gh release view "v$VERSION" &>/dev/null; then
  echo "ERROR: GitHub release v$VERSION already exists."
  echo "Either bump VERSION (CHANGELOG.md + appcast.xml) or, to re-upload"
  echo "the DMG to the existing release, run:"
  echo "  gh release upload v$VERSION <dmg-path> --clobber"
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

# ── Step 1: Bump Xcode project version (idempotent) ──────────────
#
# This step is idempotent on the release VERSION: if MARKETING_VERSION
# already matches $VERSION, a prior release.sh run already bumped pbxproj
# for this release but didn't ship — reuse the existing build number
# instead of burning a fresh one on every retry. Without this, three
# failed runs in a row would advance the build number by 3 even though
# only one release is intended, and the DMG version would not match the
# appcast.xml entry committed by a previous attempt.

echo ""
echo "==========================================="
echo "  Step 1: Bump Xcode Project Version"
echo "==========================================="
echo ""

CURRENT_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PBXPROJ" | sed 's/.*= \([0-9]*\);/\1/')
CURRENT_MARKETING=$(grep -m1 "MARKETING_VERSION" "$PBXPROJ" | sed 's/.*= \(.*\);/\1/' | tr -d ' ')

if [ "$CURRENT_MARKETING" = "$VERSION" ]; then
  NEW_BUILD=$CURRENT_BUILD
  echo "MARKETING_VERSION already at $VERSION — resuming the in-progress release."
  echo "Reusing CURRENT_PROJECT_VERSION = $NEW_BUILD (no bump)."
  echo "(To force a fresh build number, manually edit pbxproj before re-running.)"
else
  NEW_BUILD=$((CURRENT_BUILD + 1))
  echo "MARKETING_VERSION: $CURRENT_MARKETING → $VERSION"
  echo "CURRENT_PROJECT_VERSION: $CURRENT_BUILD → $NEW_BUILD"
  sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
  sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"
  echo "Updated $PBXPROJ"
fi

# ── Step 2: Build, sign, notarize (skip if cached) ────────────────
#
# Build + notarize takes 5–15 min. If a previous run already produced and
# stapled a DMG for THIS build number, reuse it instead of rebuilding.
# A DMG counts as "valid for $NEW_BUILD" only if the .app inside it
# carries CFBundleVersion = $NEW_BUILD (anti-staleness: a DMG left over
# from build 60 must NOT be reused on a build-61 run).

echo ""
echo "==========================================="
echo "  Step 2: Build & Notarize"
echo "==========================================="
echo ""

REUSE_DMG=0
if [ -f "$DMG_PATH" ] && command -v hdiutil &>/dev/null; then
  ## Probe the DMG: mount read-only, read CFBundleVersion from the .app's
  ## Info.plist, unmount. Any failure → fall through to a full rebuild.
  MOUNT_POINT=$(hdiutil attach -readonly -nobrowse -mountrandom /tmp "$DMG_PATH" 2>/dev/null | grep -E '^/dev/' | tail -1 | awk '{print $NF}')
  if [ -n "$MOUNT_POINT" ] && [ -f "$MOUNT_POINT/$APP_NAME.app/Contents/Info.plist" ]; then
    DMG_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$MOUNT_POINT/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || echo "")
    DMG_MARKETING=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$MOUNT_POINT/$APP_NAME.app/Contents/Info.plist" 2>/dev/null || echo "")
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true

    if [ "$DMG_BUILD" = "$NEW_BUILD" ] && [ "$DMG_MARKETING" = "$VERSION" ]; then
      ## Also confirm the DMG is stapled — an un-notarized DMG would still
      ## carry the right CFBundleVersion but fail Gatekeeper for users.
      if xcrun stapler validate "$DMG_PATH" &>/dev/null; then
        echo "Cached DMG found at $DMG_PATH (build $DMG_BUILD, $DMG_MARKETING, stapled)."
        echo "Skipping rebuild. Delete the DMG to force a fresh build."
        REUSE_DMG=1
      fi
    fi
  fi
fi

if [ "$REUSE_DMG" = "0" ]; then
  ./scripts/build-release.sh "$VERSION"
fi

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

## Replace the build/signature/size in the <item> block for this version.
## Uses regex against the full tag (e.g. <sparkle:version>X</sparkle:version>)
## instead of placeholder gsub, so a re-run after a partially failed release
## overwrites stale values left by the prior attempt. The template comment
## block has its own <item>...</item> but uses Version X.X.X, so the
## `index(buf, ver)` guard skips it.
awk -v sig="$SIGNATURE" -v size="$DMG_SIZE_BYTES" -v ver="$VERSION" -v build="$NEW_BUILD" '
  /<item>/ { in_item = 1; buf = "" }
  in_item {
    buf = buf $0 "\n"
  }
  in_item && /<\/item>/ {
    in_item = 0
    if (index(buf, ver)) {
      gsub(/<sparkle:version>[^<]*<\/sparkle:version>/, "<sparkle:version>" build "</sparkle:version>", buf)
      gsub(/sparkle:edSignature="[^"]*"/, "sparkle:edSignature=\"" sig "\"", buf)
      gsub(/length="[^"]*"/, "length=\"" size "\"", buf)
    }
    printf "%s", buf
    next
  }
  !in_item { print }
' appcast.xml > appcast.xml.tmp && mv appcast.xml.tmp appcast.xml

echo "Updated appcast.xml with build number ($NEW_BUILD), signature, and file size."

## Verify the entry now carries the freshly-computed values — not stale ones
## from a prior failed run. grep -F for the exact strings; anything mismatched
## means the substitution didn't take effect on the right line.
VERSION_BLOCK=$(awk -v ver="$VERSION" '
  /shortVersionString>/ && index($0, ver) { in_ver = 1 }
  in_ver { print }
  in_ver && /<\/item>/ { exit }
' appcast.xml)

if ! echo "$VERSION_BLOCK" | grep -qF "<sparkle:version>$NEW_BUILD</sparkle:version>"; then
  echo "ERROR: appcast.xml entry for $VERSION does not carry expected build number $NEW_BUILD"
  exit 1
fi
if ! echo "$VERSION_BLOCK" | grep -qF "sparkle:edSignature=\"$SIGNATURE\""; then
  echo "ERROR: appcast.xml entry for $VERSION does not carry the freshly-computed Sparkle signature"
  exit 1
fi
if ! echo "$VERSION_BLOCK" | grep -qF "length=\"$DMG_SIZE_BYTES\""; then
  echo "ERROR: appcast.xml entry for $VERSION does not carry expected DMG size $DMG_SIZE_BYTES"
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

## Build steps rewrite some tracked files (e.g. Package.resolved on every
## xcodebuild archive) but Step 6 only commits appcast.xml + project.pbxproj.
## Discard the build leftovers now — otherwise `git checkout main` quietly
## carries them across and `git merge develop` aborts with
## "Your local changes to the following files would be overwritten by merge".
if ! git diff --quiet; then
  echo "Discarding build-artifact working-tree changes before merge:"
  git diff --name-only
  git restore .
fi

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
