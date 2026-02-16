# Release Guide

## Prerequisites

Before your first release, complete the one-time setup below. For subsequent releases, skip straight to [Releasing a New Version](#releasing-a-new-version).

### One-Time Setup

#### 1. Apple credentials

Create `.env` from the example and fill in your values:

```bash
cp .env.example .env
```

Required variables:

```
APPLE_ID=your@email.com
APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
TEAM_ID=EKKL63HDHJ
```

Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com).

#### 2. Sparkle signing tools

Download and extract Sparkle tools (used for signing DMGs for auto-updates):

```bash
mkdir -p sparkle-tools
curl -L -o /tmp/Sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-2.8.1.tar.xz
tar -xJf /tmp/Sparkle.tar.xz -C sparkle-tools --strip-components=1
rm /tmp/Sparkle.tar.xz
```

If you don't have signing keys yet:

```bash
./sparkle-tools/bin/generate_keys
```

Copy the public key and set it in Xcode → Target → Info → `SUPublicEDKey`.

#### 3. GhosttyKit.xcframework

The terminal backend must be built from the Ghostty source. You only need to do this once (and again when updating Ghostty):

```bash
cd ~/projects/ghostty
zig build -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=native
cp -R macos/GhosttyKit.xcframework /path/to/slothy-terminal/
```

If the build fails with a Metal Toolchain error:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Then retry the zig build.

---

## Releasing a New Version

### Step 1: Bump the version

Open `SlothyTerminal.xcodeproj` in Xcode, go to **Target → General**:

- **Marketing Version** — increment (e.g. `2026.2.5` → `2026.2.6`)
- **Build** — increment (e.g. `7` → `8`)

Or edit `project.pbxproj` directly — update both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in **both** Debug and Release configurations.

### Step 2: Build, notarize, and create DMG

```bash
./scripts/build-release.sh 2026.2.6
```

This script:
1. Archives a Release build
2. Exports the `.app`
3. Submits to Apple for notarization (waits for approval)
4. Staples the notarization ticket
5. Creates a DMG with an Applications symlink
6. Notarizes and staples the DMG
7. Signs with Sparkle (if `sparkle-tools/bin/sign_update` exists)

On success it prints the Sparkle signature and file size.

### Step 3: Update appcast.xml

Add a new `<item>` at the top of the `<channel>` section in `appcast.xml`. Use the signature and file size from the build script output:

```xml
<item>
  <title>Version 2026.2.6</title>
  <pubDate>Sun, 16 Feb 2026 12:00:00 +0000</pubDate>
  <sparkle:version>8</sparkle:version>
  <sparkle:shortVersionString>2026.2.6</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
  <description><![CDATA[
    <h2>What's New</h2>
    <ul>
      <li>Your changes here</li>
    </ul>
  ]]></description>
  <enclosure
    url="https://github.com/maximgorbatyuk/slothy-terminal/releases/download/v2026.2.6/SlothyTerminal-2026.2.6.dmg"
    type="application/octet-stream"
    sparkle:edSignature="PASTE_SIGNATURE_HERE"
    length="FILE_SIZE_IN_BYTES"
  />
</item>
```

Fields to fill in:
- `<pubDate>` — current date in RFC 2822 format
- `<sparkle:version>` — the build number from Step 1
- `<sparkle:shortVersionString>` — the marketing version from Step 1
- `sparkle:edSignature` — from build script output (or run `./sparkle-tools/bin/sign_update build/SlothyTerminal-2026.2.6.dmg`)
- `length` — from build script output (or run `stat -f%z build/SlothyTerminal-2026.2.6.dmg`)

### Step 4: Commit and push

```bash
git add appcast.xml SlothyTerminal.xcodeproj/project.pbxproj
git commit -m "Release v2026.2.6"
git push
```

### Step 5: Create GitHub release

```bash
gh release create v2026.2.6 \
  build/SlothyTerminal-2026.2.6.dmg \
  --title "SlothyTerminal v2026.2.6" \
  --notes "- Your changes here"
```

Or create it manually at https://github.com/maximgorbatyuk/slothy-terminal/releases:
1. Tag: `v2026.2.6`
2. Title: `SlothyTerminal v2026.2.6`
3. Upload: `build/SlothyTerminal-2026.2.6.dmg`
4. Publish

### Step 6: Verify

Open the app and go to **SlothyTerminal → Check for Updates**. Sparkle should detect the new version and offer to install.

---

## Quick Reference

| Step | Command |
|------|---------|
| Build xcframework | `cd ~/projects/ghostty && zig build -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=native && cp -R macos/GhosttyKit.xcframework /path/to/slothy-terminal/` |
| Release build | `./scripts/build-release.sh VERSION` |
| Sign DMG manually | `./sparkle-tools/bin/sign_update build/SlothyTerminal-VERSION.dmg` |
| Get file size | `stat -f%z build/SlothyTerminal-VERSION.dmg` |
| Create GitHub release | `gh release create vVERSION build/SlothyTerminal-VERSION.dmg --title "SlothyTerminal vVERSION"` |

## Versioning Scheme

- **Marketing Version** (`MARKETING_VERSION`): `YYYY.M.PATCH` (e.g. `2026.2.6`). Shown to users.
- **Build Number** (`CURRENT_PROJECT_VERSION`): monotonically increasing integer (e.g. `8`). Used by Sparkle to determine update order.
- **Git Tag**: `vYYYY.M.PATCH` (e.g. `v2026.2.6`).

Both the marketing version and build number must be updated in the Xcode project for **both** Debug and Release configurations before building.

---

## Copy-Paste Release Sequence

Replace `VERSION` with the target version (e.g. `2026.2.6`) and `BUILD_NUM` with the next build number.

```bash
# 1. Rebuild GhosttyKit (skip if Ghostty source hasn't changed)
cd ~/projects/ghostty && \
  zig build -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=native && \
  cp -R macos/GhosttyKit.xcframework ~/projects/macos/SlothyTerminal/

# 2. Go to the project
cd ~/projects/macos/SlothyTerminal

# 3. Build, notarize, create DMG
./scripts/build-release.sh VERSION

# 4. Update appcast.xml (use signature and size from script output)
# Then commit and push
git add appcast.xml SlothyTerminal.xcodeproj/project.pbxproj
git commit -m "Release vVERSION"
git push

# 5. Create GitHub release
gh release create vVERSION \
  build/SlothyTerminal-VERSION.dmg \
  --title "SlothyTerminal vVERSION" \
  --notes "- Changes here"
```
