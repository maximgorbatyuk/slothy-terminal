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

## Updating Embedded Libghostty

SlothyTerminal embeds [libghostty](https://github.com/ghostty-org/ghostty) via a pre-built `GhosttyKit.xcframework`. When Ghostty releases a new version, follow the steps below to integrate it.

### When to update

- A new Ghostty release is tagged (check [releases](https://github.com/ghostty-org/ghostty/releases) or `git log` in your local clone).
- A bug fix or feature you need has landed on Ghostty's `main` branch.
- A SlothyTerminal build starts failing against the current xcframework (API changes).

### Step 1: Pull the latest Ghostty source

```bash
cd ~/projects/ghostty
git fetch --all --tags
git checkout main && git pull
```

To pin to a specific release tag instead of `main`:

```bash
git checkout v1.2.0   # replace with the actual tag
```

### Step 2: Rebuild GhosttyKit.xcframework

```bash
cd ~/projects/ghostty
zig build -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=native
```

This produces `macos/GhosttyKit.xcframework/` containing the static library and Metal shaders.

If the build fails:

| Error | Fix |
|-------|-----|
| Metal Toolchain not found | `xcodebuild -downloadComponent MetalToolchain` |
| Zig version mismatch | Install the Zig version specified in Ghostty's `build.zig.zon` (check `minimum_zig_version`). Use [zigup](https://github.com/marler36/zigup) or `brew install zig` |
| Xcode CLI tools missing | `xcode-select --install` |

### Step 3: Copy xcframework into SlothyTerminal

```bash
rm -rf ~/projects/macos/SlothyTerminal/GhosttyKit.xcframework
cp -R ~/projects/ghostty/macos/GhosttyKit.xcframework ~/projects/macos/SlothyTerminal/
```

### Step 4: Check for API changes

Open the project in Xcode and build:

```bash
cd ~/projects/macos/SlothyTerminal
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build
```

If the build fails, the Ghostty C API has changed. The files that call libghostty directly are:

| File | What it does |
|------|--------------|
| `SlothyTerminal/Terminal/GhosttyApp.swift` | App singleton, config, C callback trampolines |
| `SlothyTerminal/Terminal/GhosttySurfaceView.swift` | Surface lifecycle, size, keyboard, mouse, IME |

Common API changes to look for:

- **New or renamed fields in `ghostty_runtime_config_s`** — the callback struct passed to `ghostty_app_new`. Compare with Ghostty's `src/apprt/embedded.zig` (`RuntimeConfig`).
- **New action tags in `ghostty_action_s`** — the `ghosttyAction` trampoline switches on `action.tag`. Check Ghostty's `src/apprt/action.zig` for new cases.
- **Changed function signatures** — `ghostty_surface_new`, `ghostty_surface_set_size`, `ghostty_surface_key`, `ghostty_surface_mouse_*`, `ghostty_surface_ime_point`, etc. Compare with `src/apprt/embedded.zig`.
- **New config keys** — `ghostty_config_*` functions. Check `src/config.zig`.

Use Ghostty's own macOS app as the reference implementation:

```
~/projects/ghostty/macos/Sources/Ghostty/
├── Ghostty.App.swift                 # App lifecycle (compare with GhosttyApp.swift)
└── Surface View/
    ├── SurfaceView_AppKit.swift      # NSView + NSTextInputClient (compare with GhosttySurfaceView.swift)
    └── SurfaceScrollView.swift       # Scroll wrapper (our app doesn't use this)
```

### Step 5: Run tests

```bash
swift test
```

The SwiftPM test target does not link against GhosttyKit (chat engine and parser tests only), but verify nothing is broken.

### Step 6: Smoke test

Run the app and verify:

1. A plain terminal tab launches and renders the shell prompt correctly (no duplicate lines).
2. Keyboard input works (type a command, press Enter).
3. IME input works (switch to a CJK input method, compose, confirm).
4. Mouse scroll works.
5. Copy/paste works (`Cmd+C` with selection, `Cmd+V`).
6. A Claude CLI tab launches and runs without errors.
7. Closing a tab doesn't crash.
8. Window resize reflows the terminal content.

### Step 7: Commit

```bash
cd ~/projects/macos/SlothyTerminal
git add GhosttyKit.xcframework SlothyTerminal/Terminal/
git commit -m "Update GhosttyKit.xcframework to Ghostty <version>"
```

### Troubleshooting

**Terminal renders but the prompt duplicates on startup**

Multiple `sizeDidChange` calls are firing during surface creation. Ensure `layout()` is the only caller of `sizeDidChange` in `GhosttySurfaceView.swift`. Do NOT call it from `createSurface`, `viewDidMoveToWindow`, or `setFrameSize`.

**Metal renderer reports UNHEALTHY**

Check the Xcode console for `Ghostty renderer health is UNHEALTHY`. This usually means the Metal layer setup changed. Compare `viewDidMoveToWindow` and `viewDidChangeBackingProperties` with Ghostty's `SurfaceView_AppKit.swift`.

**Clipboard operations fail silently**

The `ghosttyReadClipboard` / `ghosttyWriteClipboard` callbacks extract the surface view via `Unmanaged<GhosttySurfaceView>.fromOpaque(userdata)`. If the userdata pointer type changed, these will crash or silently fail. Check `ghostty_runtime_config_s` callback signatures.

**IME candidate window appears in the wrong position**

`firstRect(forCharacterRange:)` calls `ghostty_surface_ime_point`. If the returned point format changed (e.g. coordinate system or units), the candidate window will be misplaced. Compare with Ghostty's implementation.

**Process hangs on exit**

`destroySurface()` calls `ghostty_surface_free`. If the API now requires additional cleanup (e.g. cancelling async IO first), the process may hang. Check `src/apprt/embedded.zig` for changes to surface teardown.

---

## Quick Reference

| Step | Command |
|------|---------|
| Update Ghostty source | `cd ~/projects/ghostty && git pull` |
| Build xcframework | `cd ~/projects/ghostty && zig build -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=native` |
| Copy xcframework | `rm -rf ~/projects/macos/SlothyTerminal/GhosttyKit.xcframework && cp -R ~/projects/ghostty/macos/GhosttyKit.xcframework ~/projects/macos/SlothyTerminal/` |
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
