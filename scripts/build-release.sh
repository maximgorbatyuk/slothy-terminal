#!/bin/bash
set -e

source "$(dirname "$0")/lib/colors.sh"

# SlothyTerminal Build Script
# Usage: ./scripts/build-release.sh [VERSION]
# Example: ./scripts/build-release.sh 2026.2.1

# Load .env file if it exists
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# Configuration
VERSION="${1:-2026.2.1}"
BUILD_DIR="./build"
APP_NAME="SlothyTerminal"
KEYCHAIN_PROFILE="AC_PASSWORD"
TEAM_ID="${TEAM_ID:-EKKL63HDHJ}"

header "$APP_NAME Release Build — $VERSION (team $TEAM_ID)"

# Ensure GhosttyKit binary dependency is present.
if [ ! -d "GhosttyKit.xcframework" ]; then
  err "GhosttyKit.xcframework not found in project root."
  info "This release requires libghostty binaries to be available before archiving."
  exit 1
fi

# Check if credentials are stored
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null; then
  warn "Notarization credentials not found."

  # Check if .env has the required values
  if [ -n "$APPLE_ID" ] && [ -n "$APP_SPECIFIC_PASSWORD" ]; then
    info "Found credentials in .env, storing in Keychain..."
    xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \
      --apple-id "$APPLE_ID" \
      --team-id "$TEAM_ID" \
      --password "$APP_SPECIFIC_PASSWORD"
    ok "Credentials stored successfully."
  else
    err "To fix this, either:"
    info ""
    info "Option 1: Create .env file with:"
    info "  APPLE_ID=your@email.com"
    info "  APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx"
    info "  TEAM_ID=$TEAM_ID"
    info ""
    info "Option 2: Run manually:"
    info "  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
    info "    --apple-id \"your@email.com\" \\"
    info "    --team-id \"$TEAM_ID\" \\"
    info "    --password \"your-app-specific-password\""
    exit 1
  fi
fi

# Clean previous build
step "[1/8] Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Archive
# GhosttyKit.xcframework is built for arm64 only (via -Dxcframework-target=native).
# Restrict the archive to arm64 to match. macOS 15.0+ runs on Apple Silicon
# (or Rosetta 2), so x86_64 is not needed.
step "[2/8] Creating archive (arm64)"
xcodebuild -scheme "$APP_NAME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  archive \
  2>&1 | dim_lines

if [ ! -d "$BUILD_DIR/$APP_NAME.xcarchive" ]; then
  err "Archive failed"
  exit 1
fi
echo "Archive created successfully"

# Export
#
# `xcodebuild -exportArchive` has been observed to fail intermittently with
# "IDEDistributionCopyItemStep ... Copy failed" on otherwise-valid archives
# (Xcode 16 race with the file system / signing daemon). The retry below
# costs ~30 s on the rare failure and saves a full re-archive (5–10 min).
# Output is not filtered — silence on transient failures was the root cause
# of two earlier "what's happening?" stalls during 2026.3.14.
step "[3/8] Exporting app"
EXPORT_TRIES=0
EXPORT_MAX_TRIES=2
while [ $EXPORT_TRIES -lt $EXPORT_MAX_TRIES ]; do
  EXPORT_TRIES=$((EXPORT_TRIES + 1))
  info "  exportArchive attempt $EXPORT_TRIES/$EXPORT_MAX_TRIES..."
  rm -rf "$BUILD_DIR/export"
  if xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    -exportPath "$BUILD_DIR/export" \
    -exportOptionsPlist ExportOptions.plist 2>&1 | dim_lines
  then
    if [ -d "$BUILD_DIR/export/$APP_NAME.app" ]; then
      break
    fi
  fi

  if [ $EXPORT_TRIES -lt $EXPORT_MAX_TRIES ]; then
    warn "exportArchive failed; retrying in 5s..."
    sleep 5
  fi
done

if [ ! -d "$BUILD_DIR/export/$APP_NAME.app" ]; then
  err "Export failed after $EXPORT_MAX_TRIES attempts — app not found"
  exit 1
fi
ok "Export completed successfully"

# Create ZIP for notarization
step "[4/8] Creating ZIP for notarization"
ditto -c -k --keepParent "$BUILD_DIR/export/$APP_NAME.app" "$BUILD_DIR/$APP_NAME.zip"
ok "ZIP created: $BUILD_DIR/$APP_NAME.zip"

# Notarize
step "[5/8] Submitting for notarization"
info "This may take several minutes..."
xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait 2>&1 | dim_lines

# Staple app
step "[6/8] Stapling notarization ticket to app"
xcrun stapler staple "$BUILD_DIR/export/$APP_NAME.app" 2>&1 | dim_lines
ok "Stapling completed"

# Create DMG with Applications symlink
step "[7/8] Creating DMG"

# Create temporary folder for DMG contents
DMG_TEMP="$BUILD_DIR/dmg-contents"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp folder
cp -R "$BUILD_DIR/export/$APP_NAME.app" "$DMG_TEMP/"

# Create symlink to Applications folder
ln -s /Applications "$DMG_TEMP/Applications"

# Create DMG from temp folder
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_TEMP" \
  -ov \
  -format UDZO \
  "$BUILD_DIR/$APP_NAME-$VERSION.dmg" 2>&1 | dim_lines

# Clean up temp folder
rm -rf "$DMG_TEMP"

ok "DMG created: $BUILD_DIR/$APP_NAME-$VERSION.dmg"

# Notarize and staple DMG
step "[8/8] Notarizing and stapling DMG"
xcrun notarytool submit "$BUILD_DIR/$APP_NAME-$VERSION.dmg" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait 2>&1 | dim_lines

xcrun stapler staple "$BUILD_DIR/$APP_NAME-$VERSION.dmg" 2>&1 | dim_lines
ok "DMG notarized and stapled"

# Verify
header "Verification"

info "App signature:"
codesign -dv "$BUILD_DIR/export/$APP_NAME.app" 2>&1 | grep -E '(Identifier|TeamIdentifier|Signature)' | dim_lines || true

info ""
info "Gatekeeper check (app):"
spctl -a -vv "$BUILD_DIR/export/$APP_NAME.app" 2>&1 | dim_lines || true

info ""
info "Gatekeeper check (DMG):"
spctl -a -vv --type install "$BUILD_DIR/$APP_NAME-$VERSION.dmg" 2>&1 | dim_lines || true

# Calculate file size
DMG_SIZE=$(du -h "$BUILD_DIR/$APP_NAME-$VERSION.dmg" | cut -f1)
DMG_SIZE_BYTES=$(stat -f%z "$BUILD_DIR/$APP_NAME-$VERSION.dmg")

# Sign for Sparkle (if sign_update tool exists)
echo ""
header "Sparkle Signing"
SPARKLE_BIN="./sparkle-tools/bin/sign_update"
if [ -f "$SPARKLE_BIN" ]; then
  info "Signing DMG for Sparkle updates..."
  SPARKLE_SIGN=$($SPARKLE_BIN "$BUILD_DIR/$APP_NAME-$VERSION.dmg")
  info ""
  info "Sparkle signature generated:"
  info "$SPARKLE_SIGN"
  info ""
  info "Add this to appcast.xml:"
  info "  sparkle:edSignature=\"$(echo "$SPARKLE_SIGN" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)\""
  info "  length=\"$DMG_SIZE_BYTES\""
else
  warn "Sparkle sign_update tool not found at $SPARKLE_BIN"
  info ""
  info "To enable Sparkle signing:"
  info "  1. Download Sparkle from: https://github.com/sparkle-project/Sparkle/releases/latest"
  info "  2. Extract to ./sparkle-tools/"
  info "  3. Run this script again"
  info ""
  info "Or sign manually:"
  info "  ./sparkle-tools/bin/sign_update \"$BUILD_DIR/$APP_NAME-$VERSION.dmg\""
fi

header "Build Complete!"
info "  DMG:  $BUILD_DIR/$APP_NAME-$VERSION.dmg"
info "  Size: $DMG_SIZE ($DMG_SIZE_BYTES bytes)"
info ""
info "  Next steps:"
info "  1. Test the DMG installation"
info "  2. Sign DMG with Sparkle (if not done above):"
info "     ./sparkle-tools/bin/sign_update $BUILD_DIR/$APP_NAME-$VERSION.dmg"
info "  3. Update appcast.xml with signature and file size"
info "  4. Commit and push appcast.xml"
info "  5. Go to: https://github.com/maximgorbatyuk/slothy-terminal/releases"
info "  6. Create new release with tag: v$VERSION"
info "  7. Upload: $APP_NAME-$VERSION.dmg"
