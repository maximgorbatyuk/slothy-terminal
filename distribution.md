# SlothyTerminal Distribution Guide

This guide explains how to build, sign, notarize, and distribute SlothyTerminal outside the Mac App Store.

## App Information

| Property | Value |
|----------|-------|
| App Name | SlothyTerminal |
| Bundle ID | mgorbatyuk.dev.SlothyTerminal |
| Team ID | EKKL63HDHJ |
| Developer | Maxim Gorbatyuk |
| GitHub | https://github.com/maximgorbatyuk/slothy-terminal |

## Prerequisites

- macOS with Xcode installed
- Apple Developer Program membership
- Developer ID Application certificate installed in Keychain

## Step 1: Verify Your Certificate

```bash
# List your signing identities
security find-identity -v -p codesigning
```

Look for: `Developer ID Application: Maxim Gorbatyuk (EKKL63HDHJ)`

## Step 2: Store Notarization Credentials (One-Time Setup)

Create an app-specific password:
1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign In → Security → App-Specific Passwords
3. Generate a new password named "SlothyTerminal Notarization"

Store credentials in Keychain:
```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "YOUR_APPLE_ID_EMAIL" \
  --team-id "EKKL63HDHJ" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

## Step 3: Build and Distribute

### Quick Method (Automated Script)

```bash
# Make script executable (first time only)
chmod +x scripts/build-release.sh

# Build release (specify version)
./scripts/build-release.sh 2026.1.1
```

The script will:
1. Create a release archive
2. Export the signed app
3. Submit for notarization
4. Create a DMG file
5. Notarize the DMG
6. Verify everything

Output: `build/SlothyTerminal-2026.1.1.dmg`

### Manual Method

#### 3.1 Create Archive

**Using Xcode:**
1. Open `SlothyTerminal.xcodeproj`
2. Set scheme to **Release**: Product → Scheme → Edit Scheme → Run → Build Configuration → Release
3. Product → Archive
4. Wait for completion

**Using Terminal:**
```bash
xcodebuild -scheme SlothyTerminal \
  -configuration Release \
  -archivePath ./build/SlothyTerminal.xcarchive \
  archive
```

#### 3.2 Export App

**Using Xcode:**
1. Window → Organizer
2. Select the archive → Distribute App
3. Select "Developer ID" → Next
4. Select "Upload" for automatic notarization
5. Wait for notarization → Export

**Using Terminal:**
```bash
xcodebuild -exportArchive \
  -archivePath ./build/SlothyTerminal.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ExportOptions.plist
```

#### 3.3 Notarize (if exported manually)

```bash
# Create ZIP
ditto -c -k --keepParent "./build/export/SlothyTerminal.app" "./build/SlothyTerminal.zip"

# Submit for notarization
xcrun notarytool submit "./build/SlothyTerminal.zip" \
  --keychain-profile "AC_PASSWORD" \
  --wait

# Staple the ticket
xcrun stapler staple "./build/export/SlothyTerminal.app"
```

#### 3.4 Create DMG

```bash
# Create DMG
hdiutil create \
  -volname "SlothyTerminal" \
  -srcfolder "./build/export/SlothyTerminal.app" \
  -ov \
  -format UDZO \
  "./build/SlothyTerminal-2026.1.1.dmg"

# Notarize DMG
xcrun notarytool submit "./build/SlothyTerminal-2026.1.1.dmg" \
  --keychain-profile "AC_PASSWORD" \
  --wait

# Staple DMG
xcrun stapler staple "./build/SlothyTerminal-2026.1.1.dmg"
```

## Step 4: Verify Before Upload

```bash
# Check app signature
codesign -dv --verbose=4 "./build/export/SlothyTerminal.app"

# Verify Gatekeeper approval
spctl -a -vv "./build/export/SlothyTerminal.app"
# Expected: "accepted" and "source=Notarized Developer ID"

# Verify DMG
spctl -a -vv --type install "./build/SlothyTerminal-2026.1.1.dmg"
```

## Step 5: Upload to GitHub

1. Go to https://github.com/maximgorbatyuk/slothy-terminal/releases
2. Click "Draft a new release"
3. Create tag: `v2026.1.1`
4. Title: `SlothyTerminal v2026.1.1`
5. Add release notes
6. Upload `SlothyTerminal-2026.1.1.dmg`
7. Publish release

## Version Management

Before each release, update the version in Xcode:

1. Select project → General tab
2. Update **Version** (e.g., 2026.1.2)
3. Update **Build** number

The app uses semantic versioning: `YEAR.MAJOR.MINOR`

## Troubleshooting

### "Developer ID Application" certificate not found

```bash
# Check installed certificates
security find-identity -v -p codesigning | grep "Developer ID"
```

If missing, download from [developer.apple.com](https://developer.apple.com/account/resources/certificates/list).

### Notarization fails

Check the detailed log:
```bash
# Get submission history
xcrun notarytool history --keychain-profile "AC_PASSWORD"

# Get log for specific submission
xcrun notarytool log <SUBMISSION_ID> --keychain-profile "AC_PASSWORD"
```

Common issues:
- Unsigned nested frameworks
- Hardened runtime not enabled
- Missing entitlements

### "App is damaged" on user's Mac

The app wasn't properly notarized or stapled. Re-run:
```bash
xcrun notarytool submit "SlothyTerminal.app.zip" --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple "SlothyTerminal.app"
```

### Users see security warning

If users see "Apple cannot check it for malicious software":
1. User should right-click → Open (first time only)
2. Or verify notarization was successful with `spctl -a -vv`

## File Checklist

Before building, ensure these files exist:

- [x] `ExportOptions.plist` - Export configuration (Team ID: EKKL63HDHJ)
- [x] `scripts/build-release.sh` - Automated build script
- [x] `scripts/update-appcast.sh` - Appcast entry generator
- [x] `SlothyTerminal/Resources/Config.release.json` - Release configuration
- [x] `SlothyTerminal/Services/UpdateManager.swift` - Sparkle update manager
- [x] `appcast.xml` - Sparkle appcast file

## Automatic Updates (Sparkle)

SlothyTerminal uses the [Sparkle](https://sparkle-project.org/) framework for automatic updates.

### Initial Setup (One-Time)

1. **Add Sparkle package in Xcode:**
   - File → Add Package Dependencies
   - URL: `https://github.com/sparkle-project/Sparkle`
   - Version: 2.x (Up to Next Major)

2. **Download Sparkle tools:**
   ```bash
   # Download latest Sparkle release
   curl -L https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-2.7.0.tar.xz -o Sparkle.tar.xz

   # Extract to sparkle-tools/
   mkdir -p sparkle-tools
   tar -xJf Sparkle.tar.xz -C sparkle-tools
   rm Sparkle.tar.xz
   ```

3. **Generate EdDSA key pair:**
   ```bash
   ./sparkle-tools/bin/generate_keys
   ```

   This outputs:
   - **Private key** - Stored in Keychain automatically
   - **Public key** - Add to Info.plist (see below)

4. **Configure Info.plist:**

   Add these entries in Xcode (Target → Info → Custom macOS Application Target Properties):

   | Key | Value |
   |-----|-------|
   | `SUFeedURL` | `https://raw.githubusercontent.com/maximgorbatyuk/slothy-terminal/main/appcast.xml` |
   | `SUPublicEDKey` | `<your-public-key-from-step-3>` |
   | `SUEnableAutomaticChecks` | `YES` |

### Security Notes

- **NEVER** commit the private key to git
- The private key is stored in macOS Keychain
- All updates are verified against the EdDSA signature

## Release Checklist

- [ ] Update version number in Xcode
- [ ] Increment build number
- [ ] Test app in Release configuration
- [ ] Run `./scripts/build-release.sh X.X.X`
- [ ] Verify with `spctl -a -vv`
- [ ] Sign DMG with Sparkle: `./sparkle-tools/bin/sign_update build/SlothyTerminal-X.X.X.dmg`
- [ ] Update appcast.xml with new entry (use `./scripts/update-appcast.sh` helper)
- [ ] Commit and push appcast.xml
- [ ] Test DMG installation on clean Mac (if possible)
- [ ] Create GitHub release with DMG
- [ ] Update release notes
- [ ] Verify update works: App menu → Check for Updates
