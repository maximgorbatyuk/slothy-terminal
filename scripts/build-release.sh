#!/bin/bash
set -e

# SlothyTerminal Build Script
# Usage: ./scripts/build-release.sh [VERSION]
# Example: ./scripts/build-release.sh 2026.1.1

# Configuration
VERSION="${1:-2026.1.1}"
BUILD_DIR="./build"
APP_NAME="SlothyTerminal"
KEYCHAIN_PROFILE="AC_PASSWORD"
TEAM_ID="EKKL63HDHJ"

echo "==========================================="
echo "  $APP_NAME Release Build"
echo "  Version: $VERSION"
echo "  Team ID: $TEAM_ID"
echo "==========================================="

# Check if credentials are stored
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null; then
  echo ""
  echo "ERROR: Notarization credentials not found."
  echo ""
  echo "Run this command first to store your credentials:"
  echo ""
  echo "  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
  echo "    --apple-id \"YOUR_APPLE_ID_EMAIL\" \\"
  echo "    --team-id \"$TEAM_ID\" \\"
  echo "    --password \"YOUR_APP_SPECIFIC_PASSWORD\""
  echo ""
  exit 1
fi

# Clean previous build
echo ""
echo "[1/8] Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Archive
echo ""
echo "[2/8] Creating archive..."
xcodebuild -scheme "$APP_NAME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  archive \
  2>&1 | grep -E '(Archive Succeeded|BUILD SUCCEEDED|error:|warning:|\*\*)' || true

if [ ! -d "$BUILD_DIR/$APP_NAME.xcarchive" ]; then
  echo "ERROR: Archive failed"
  exit 1
fi
echo "Archive created successfully"

# Export
echo ""
echo "[3/8] Exporting app..."
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist ExportOptions.plist \
  2>&1 | grep -E '(Export Succeeded|error:|warning:|\*\*)' || true

if [ ! -d "$BUILD_DIR/export/$APP_NAME.app" ]; then
  echo "ERROR: Export failed - app not found"
  exit 1
fi
echo "Export completed successfully"

# Create ZIP for notarization
echo ""
echo "[4/8] Creating ZIP for notarization..."
ditto -c -k --keepParent "$BUILD_DIR/export/$APP_NAME.app" "$BUILD_DIR/$APP_NAME.zip"
echo "ZIP created: $BUILD_DIR/$APP_NAME.zip"

# Notarize
echo ""
echo "[5/8] Submitting for notarization..."
echo "This may take several minutes..."
xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

# Staple app
echo ""
echo "[6/8] Stapling notarization ticket to app..."
xcrun stapler staple "$BUILD_DIR/export/$APP_NAME.app"
echo "Stapling completed"

# Create DMG
echo ""
echo "[7/8] Creating DMG..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$BUILD_DIR/export/$APP_NAME.app" \
  -ov \
  -format UDZO \
  "$BUILD_DIR/$APP_NAME-$VERSION.dmg"
echo "DMG created: $BUILD_DIR/$APP_NAME-$VERSION.dmg"

# Notarize and staple DMG
echo ""
echo "[8/8] Notarizing and stapling DMG..."
xcrun notarytool submit "$BUILD_DIR/$APP_NAME-$VERSION.dmg" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

xcrun stapler staple "$BUILD_DIR/$APP_NAME-$VERSION.dmg"
echo "DMG notarized and stapled"

# Verify
echo ""
echo "==========================================="
echo "  Verification"
echo "==========================================="

echo ""
echo "App signature:"
codesign -dv "$BUILD_DIR/export/$APP_NAME.app" 2>&1 | grep -E '(Identifier|TeamIdentifier|Signature)' || true

echo ""
echo "Gatekeeper check (app):"
spctl -a -vv "$BUILD_DIR/export/$APP_NAME.app" 2>&1 || true

echo ""
echo "Gatekeeper check (DMG):"
spctl -a -vv --type install "$BUILD_DIR/$APP_NAME-$VERSION.dmg" 2>&1 || true

# Calculate file size
DMG_SIZE=$(du -h "$BUILD_DIR/$APP_NAME-$VERSION.dmg" | cut -f1)
DMG_SIZE_BYTES=$(stat -f%z "$BUILD_DIR/$APP_NAME-$VERSION.dmg")

# Sign for Sparkle (if sign_update tool exists)
echo ""
echo "==========================================="
echo "  Sparkle Signing"
echo "==========================================="
SPARKLE_BIN="./sparkle-tools/bin/sign_update"
if [ -f "$SPARKLE_BIN" ]; then
  echo "Signing DMG for Sparkle updates..."
  SPARKLE_SIGN=$($SPARKLE_BIN "$BUILD_DIR/$APP_NAME-$VERSION.dmg")
  echo ""
  echo "Sparkle signature generated:"
  echo "$SPARKLE_SIGN"
  echo ""
  echo "Add this to appcast.xml:"
  echo "  sparkle:edSignature=\"$(echo "$SPARKLE_SIGN" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)\""
  echo "  length=\"$DMG_SIZE_BYTES\""
else
  echo "WARNING: Sparkle sign_update tool not found at $SPARKLE_BIN"
  echo ""
  echo "To enable Sparkle signing:"
  echo "  1. Download Sparkle from: https://github.com/sparkle-project/Sparkle/releases/latest"
  echo "  2. Extract to ./sparkle-tools/"
  echo "  3. Run this script again"
  echo ""
  echo "Or sign manually:"
  echo "  ./sparkle-tools/bin/sign_update \"$BUILD_DIR/$APP_NAME-$VERSION.dmg\""
fi

echo ""
echo "==========================================="
echo "  Build Complete!"
echo "==========================================="
echo ""
echo "  DMG: $BUILD_DIR/$APP_NAME-$VERSION.dmg"
echo "  Size: $DMG_SIZE ($DMG_SIZE_BYTES bytes)"
echo ""
echo "  Next steps:"
echo "  1. Test the DMG installation"
echo "  2. Sign DMG with Sparkle (if not done above):"
echo "     ./sparkle-tools/bin/sign_update $BUILD_DIR/$APP_NAME-$VERSION.dmg"
echo "  3. Update appcast.xml with signature and file size"
echo "  4. Commit and push appcast.xml"
echo "  5. Go to: https://github.com/maximgorbatyuk/slothy-terminal/releases"
echo "  6. Create new release with tag: v$VERSION"
echo "  7. Upload: $APP_NAME-$VERSION.dmg"
echo ""
