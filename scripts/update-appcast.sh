#!/bin/bash

# SlothyTerminal Appcast Entry Generator
# Usage: ./scripts/update-appcast.sh VERSION BUILD_NUMBER SIGNATURE FILE_SIZE
# Example: ./scripts/update-appcast.sh 2026.1.2 2 "abc123..." 15000000

set -e

VERSION="${1}"
BUILD_NUMBER="${2}"
SIGNATURE="${3}"
FILE_SIZE="${4}"

if [ -z "$VERSION" ] || [ -z "$BUILD_NUMBER" ] || [ -z "$SIGNATURE" ] || [ -z "$FILE_SIZE" ]; then
  echo "Usage: $0 VERSION BUILD_NUMBER SIGNATURE FILE_SIZE"
  echo ""
  echo "Arguments:"
  echo "  VERSION      - Version string (e.g., 2026.1.2)"
  echo "  BUILD_NUMBER - Build number (e.g., 2)"
  echo "  SIGNATURE    - EdDSA signature from sign_update"
  echo "  FILE_SIZE    - DMG file size in bytes"
  echo ""
  echo "Example:"
  echo "  $0 2026.1.2 2 \"abc123...\" 15000000"
  echo ""
  echo "To get signature and file size, run:"
  echo "  ./sparkle-tools/bin/sign_update build/SlothyTerminal-VERSION.dmg"
  exit 1
fi

DATE=$(date -R)

echo "Add this entry to the top of the <channel> section in appcast.xml:"
echo ""
echo "------- BEGIN APPCAST ENTRY -------"
cat << EOF
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
echo "------- END APPCAST ENTRY -------"
echo ""
echo "Don't forget to:"
echo "  1. Update the release notes in the entry above"
echo "  2. Commit and push appcast.xml before creating the GitHub release"
