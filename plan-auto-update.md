# Auto-Update Implementation Plan

## Overview

Implement automatic update checking and installation for SlothyTerminal using the **Sparkle** framework with GitHub Releases as the update server.

## Technology Choice: Sparkle 2

**Sparkle** is the de-facto standard for macOS app updates outside the App Store.

**Why Sparkle:**
- Open source, widely used (used by Firefox, VLC, Sketch, etc.)
- Secure (EdDSA signatures)
- Handles download, verification, and installation
- Supports delta updates
- Works with GitHub Releases
- SwiftUI compatible

**GitHub Repository:** https://github.com/sparkle-project/Sparkle

---

## Implementation Steps

### Phase 1: Setup Sparkle Framework

#### 1.1 Add Sparkle via Swift Package Manager

```
File → Add Package Dependencies
URL: https://github.com/sparkle-project/Sparkle
Version: 2.x (Up to Next Major)
```

#### 1.2 Generate EdDSA Key Pair

Generate a key pair for signing updates:

```bash
# Download Sparkle tools
curl -L https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-2.x.x.tar.xz | tar -xJ

# Generate key pair
./bin/generate_keys
```

This outputs:
- **Private key** - Store securely, never commit to git
- **Public key** - Add to Info.plist

#### 1.3 Configure Info.plist

Add these keys to the app's Info.plist:

| Key | Value | Description |
|-----|-------|-------------|
| `SUFeedURL` | `https://raw.githubusercontent.com/maximgorbatyuk/slothy-terminal/main/appcast.xml` | URL to appcast file |
| `SUPublicEDKey` | `<your-public-key>` | EdDSA public key |
| `SUEnableAutomaticChecks` | `YES` | Enable auto-check on launch |
| `SUAutomaticallyUpdate` | `NO` | Don't auto-install (let user decide) |

---

### Phase 2: Implement Update Checker in App

#### 2.1 Create UpdateManager

```swift
// Services/UpdateManager.swift

import Foundation
import Sparkle

@Observable
class UpdateManager {
    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }
}
```

#### 2.2 Add Menu Item

Add "Check for Updates..." to the app menu:

```swift
// In SlothyTerminalApp.swift

CommandGroup(after: .appInfo) {
    Button("Check for Updates...") {
        UpdateManager.shared.checkForUpdates()
    }
    .disabled(!UpdateManager.shared.canCheckForUpdates)
}
```

#### 2.3 Add to Settings (Optional)

Add update preferences to Settings view:

```swift
// In SettingsView.swift

Section("Updates") {
    Toggle("Check for updates automatically",
           isOn: $automaticUpdateChecks)

    if let lastCheck = UpdateManager.shared.lastUpdateCheckDate {
        Text("Last checked: \(lastCheck.formatted())")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    Button("Check Now") {
        UpdateManager.shared.checkForUpdates()
    }
}
```

---

### Phase 3: Create Appcast File

#### 3.1 Appcast Structure

Create `appcast.xml` in repository root:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SlothyTerminal Updates</title>
    <link>https://github.com/maximgorbatyuk/slothy-terminal/releases</link>
    <description>Most recent updates to SlothyTerminal</description>
    <language>en</language>

    <item>
      <title>Version 2026.1.1</title>
      <pubDate>Mon, 03 Feb 2026 12:00:00 +0000</pubDate>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>2026.1.1</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>What's New</h2>
        <ul>
          <li>Initial release</li>
          <li>Terminal, Claude, and OpenCode tabs</li>
          <li>Usage statistics sidebar</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/maximgorbatyuk/slothy-terminal/releases/download/v2026.1.1/SlothyTerminal-2026.1.1.dmg"
        type="application/octet-stream"
        sparkle:edSignature="SIGNATURE_HERE"
        length="FILE_SIZE_IN_BYTES"
      />
    </item>

  </channel>
</rss>
```

#### 3.2 Signing Releases

Sign each release DMG with your private key:

```bash
# Sign the DMG
./bin/sign_update "SlothyTerminal-2026.1.1.dmg"

# Output: edSignature="xxxx..." length="yyyy"
```

Add the signature to the appcast.xml `<enclosure>` tag.

---

### Phase 4: Update Build Script

#### 4.1 Add Signing to Build Script

Update `scripts/build-release.sh` to include Sparkle signing:

```bash
# After DMG creation, sign for Sparkle
echo "Signing for Sparkle..."
SPARKLE_SIGN=$(./bin/sign_update "$BUILD_DIR/$APP_NAME-$VERSION.dmg")
echo "Add this to appcast.xml:"
echo "$SPARKLE_SIGN"
```

#### 4.2 Create Appcast Update Script

Create `scripts/update-appcast.sh`:

```bash
#!/bin/bash
VERSION=$1
SIGNATURE=$2
FILE_SIZE=$3
DATE=$(date -R)

# Generate appcast entry
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
      <li>Update description here</li>
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
```

---

### Phase 5: Release Workflow

#### 5.1 Release Checklist (Updated)

1. [ ] Update version in Xcode
2. [ ] Update `Config.release.json` if needed
3. [ ] Run `./scripts/build-release.sh X.X.X`
4. [ ] Sign DMG with Sparkle: `./bin/sign_update SlothyTerminal-X.X.X.dmg`
5. [ ] Update `appcast.xml` with new entry
6. [ ] Commit and push `appcast.xml`
7. [ ] Create GitHub release and upload DMG
8. [ ] Verify update works: Menu → Check for Updates

---

## File Structure After Implementation

```
SlothyTerminal/
├── SlothyTerminal/
│   ├── Services/
│   │   └── UpdateManager.swift      # NEW
│   └── ...
├── scripts/
│   ├── build-release.sh             # UPDATED
│   └── update-appcast.sh            # NEW
├── appcast.xml                       # NEW
├── sparkle-keys/                     # NEW (gitignored)
│   └── sparkle_private_key          # NEVER COMMIT
└── ...
```

---

## Security Considerations

1. **Private Key Security**
   - Never commit `sparkle_private_key` to git
   - Store in secure location (1Password, Keychain, etc.)
   - Add to `.gitignore`

2. **HTTPS Only**
   - Appcast URL must use HTTPS
   - GitHub raw URLs use HTTPS by default

3. **Code Signing**
   - App must be signed with Developer ID
   - Updates are verified against EdDSA signature

---

## Alternative: GitHub API Direct Check

If Sparkle is too heavy, a simpler alternative:

```swift
// Check GitHub releases API directly
func checkForUpdates() async throws -> Release? {
    let url = URL(string: "https://api.github.com/repos/maximgorbatyuk/slothy-terminal/releases/latest")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

    let currentVersion = Bundle.main.version
    if release.tagName > currentVersion {
        return release
    }
    return nil
}
```

**Pros:** Simpler, no framework needed
**Cons:** Manual download/install, no delta updates, more code to maintain

---

## Recommendation

**Use Sparkle** - It's the industry standard, well-tested, and handles all edge cases (permissions, sandboxing, signatures, delta updates, etc.).

---

## Estimated Effort

| Phase | Task | Effort |
|-------|------|--------|
| 1 | Setup Sparkle & keys | 1-2 hours |
| 2 | Implement UpdateManager | 1-2 hours |
| 3 | Create appcast.xml | 30 min |
| 4 | Update build scripts | 1 hour |
| 5 | Testing | 1-2 hours |
| **Total** | | **5-8 hours** |

---

## Next Steps

1. Approve this plan
2. I will implement Phase 1-4
3. You generate the EdDSA keys (security - should be done locally)
4. Test the update flow
