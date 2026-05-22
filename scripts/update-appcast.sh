#!/bin/bash

# SlothyTerminal Appcast Entry Generator
# Usage: ./scripts/update-appcast.sh VERSION BUILD_NUMBER SIGNATURE FILE_SIZE
# Example: ./scripts/update-appcast.sh 2026.1.2 2 "abc123..." 15000000

set -e

source "$(dirname "$0")/lib/colors.sh"

VERSION="${1}"
BUILD_NUMBER="${2}"
SIGNATURE="${3}"
FILE_SIZE="${4}"

if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ] || [ -z "$SIGNATURE" ] || [ -z "$FILE_SIZE" ]; then
  info "Usage: $0 VERSION BUILD_NUMBER SIGNATURE FILE_SIZE"
  info ""
  info "Arguments:"
  info "  VERSION      - Version string (e.g., 2026.1.2)"
  info "  BUILD_NUMBER - Build number (e.g., 2)"
  info "  SIGNATURE    - EdDSA signature from sign_update"
  info "  FILE_SIZE    - DMG file size in bytes"
  info ""
  info "Example:"
  info "  $0 2026.1.2 2 \"abc123...\" 15000000"
  info ""
  info "To get signature and file size, run:"
  info "  ./sparkle-tools/bin/sign_update build/SlothyTerminal-VERSION.dmg"
  exit 1
fi

DATE=$(date -R)

info "Add this entry to the top of the <channel> section in appcast.xml:"
info ""
header "BEGIN APPCAST ENTRY"
cat << EOF | dim_lines
    <item>
      <title>Version $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>What's New</h2>
        <ul>
          <li>TODO: Add release notes here</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/maximgorbatyuk/slothy-terminal/releases/download/v$VERSION/SlothyTerminal-$VERSION.dmg"
        type="application/octet-stream"
        sparkle:edSignature="$SIGNATURE"
        length="$FILE_SIZE"
      />
    </item>
EOF
header "END APPCAST ENTRY"
info ""
info "Don't forget to:"
info "  1. Update the release notes in the entry above"
info "  2. Commit and push appcast.xml before creating the GitHub release"
