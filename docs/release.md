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
cp -R macos/GhosttyKit.xcframework ~/projects/macos/SlothyTerminal/
```

If the build fails with a Metal Toolchain error:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Then retry the zig build.

---

## Releasing a New Version

The release pipeline is driven by `scripts/release.sh`, which is **idempotent on `VERSION`**: a partial / failed run can be re-invoked with the same version and it will resume rather than re-bump the build number. Two files have to be prepared by hand before running it; everything else is automated.

### Step 1 — Prepare `CHANGELOG.md`

Add a `[VERSION]` entry to `CHANGELOG.md`. The release script greps for `[$VERSION]` during preflight and aborts if it's missing.

### Step 2 — Prepare `appcast.xml`

Add a new `<item>` at the top of the `<channel>` section with **placeholders** for the values the script will fill in:

```xml
<item>
  <title>Version 2026.2.6</title>
  <pubDate>Sun, 16 Feb 2026 12:00:00 +0000</pubDate>
  <sparkle:version>BUILD_NUMBER</sparkle:version>
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
    sparkle:edSignature="SIGNATURE_HERE"
    length="FILE_SIZE_IN_BYTES"
  />
</item>
```

Leave the three placeholders **as literal strings** — `BUILD_NUMBER`, `SIGNATURE_HERE`, `FILE_SIZE_IN_BYTES`. The script's preflight check requires `SIGNATURE_HERE` to be present; it substitutes all three after the build.

Set `<pubDate>` to the current date in RFC 2822 format and the marketing version to the version you intend to ship.

### Step 3 — Run `release.sh`

```bash
./scripts/release.sh 2026.2.6
# or, to auto-bump the patch segment of the current MARKETING_VERSION:
./scripts/release.sh
```

What the script does, in order:

1. **Preflight** — verifies `gh` is installed and authenticated, `sparkle-tools/bin/sign_update` exists, `appcast.xml` carries the `SIGNATURE_HERE` placeholder, and `CHANGELOG.md` has a `[VERSION]` entry. If a GitHub release `vVERSION` already exists, the script exits cleanly (status 0) without touching anything.
2. **Pre-release commit** — if the working tree is dirty, stages everything and commits as `"Commit before release VERSION"`. This is destructive in the sense that *any* uncommitted file is swept in — review `git status` before invoking.
3. **Bump Xcode project version** — rewrites `MARKETING_VERSION` and increments `CURRENT_PROJECT_VERSION` in `project.pbxproj`. If `MARKETING_VERSION` is already `VERSION` (a resumed run), reuses the existing build number instead of advancing it.
4. **Build, sign, notarize** — invokes `scripts/build-release.sh`. Reuses an existing stapled DMG at `build/SlothyTerminal-VERSION.dmg` if its `CFBundleVersion` matches the bumped build number — re-runs skip the 5–15 min build when nothing has changed.
5. **Sparkle signing** — runs `sparkle-tools/bin/sign_update` against the DMG.
6. **Substitute placeholders in `appcast.xml`** — replaces `BUILD_NUMBER`, `SIGNATURE_HERE`, and `FILE_SIZE_IN_BYTES` with the real values. Verifies the substitution succeeded; aborts if any placeholder remains.
7. **Extract release notes** from the `[VERSION]` section of `CHANGELOG.md`.
8. **Commit release files** — `git add` the bumped `project.pbxproj`, updated `appcast.xml`, and the changelog; commit as `"chore: release VERSION"`.
9. **Push and merge to main** — pushes the release branch and fast-forwards `main` (this is why the GitHub release tag lands on `main`'s tip, not on the working branch).
10. **Create the GitHub release** — `gh release create vVERSION` with the extracted notes and uploads the DMG.

Output is colorized step-by-step. Pipe to `tee` with `FORCE_COLOR=1` if you want a coloured log:

```bash
FORCE_COLOR=1 ./scripts/release.sh 2026.2.6 2>&1 | tee build/release.log
```

### Step 4 — Verify

Open the app and go to **SlothyTerminal → Check for Updates**. Sparkle should detect the new version and offer to install.

### Re-running after a failure

Because `release.sh` is idempotent on `VERSION`, the safest recovery from a failed run is to re-invoke it with the same `VERSION`. The Xcode version bump, DMG cache, appcast substitution, and GitHub-release-existence check all short-circuit on second invocation. If you want to force a fresh build, delete `build/SlothyTerminal-VERSION.dmg` before re-running.

If you genuinely need a brand-new build number against the same `VERSION` (e.g. the DMG you shipped was bad), revert the pbxproj bump manually before re-running.

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
| Full release (auto-bump patch) | `./scripts/release.sh` |
| Full release (explicit version) | `./scripts/release.sh 2026.2.6` |
| Build + notarize DMG only | `./scripts/build-release.sh VERSION` |
| Sign DMG manually | `./sparkle-tools/bin/sign_update build/SlothyTerminal-VERSION.dmg` |
| Get file size | `stat -f%z build/SlothyTerminal-VERSION.dmg` |
| Inspect script log w/ colour | `FORCE_COLOR=1 ./scripts/release.sh VERSION 2>&1 \| tee build/release.log` |

## Versioning Scheme

- **Marketing Version** (`MARKETING_VERSION`): `YYYY.M.PATCH` (e.g. `2026.2.6`). Shown to users. Rewritten by `release.sh` Step 3.
- **Build Number** (`CURRENT_PROJECT_VERSION`): monotonically increasing integer. Auto-incremented by `release.sh` Step 3 (or reused on a resumed run with the same `MARKETING_VERSION`).
- **Git Tag**: `vYYYY.M.PATCH` (e.g. `v2026.2.6`). Created implicitly by `gh release create`.

Both values are written into `project.pbxproj` for the Debug and Release configurations simultaneously — `release.sh` uses a global `sed`, so manual edits should follow the same pattern.

---

## Copy-Paste Release Sequence

Replace `VERSION` with the target version (e.g. `2026.2.6`).

```bash
# 1. Rebuild GhosttyKit (skip if Ghostty source hasn't changed)
cd ~/projects/ghostty && \
  zig build -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=native && \
  cp -R macos/GhosttyKit.xcframework ~/projects/macos/SlothyTerminal/

# 2. Go to the project
cd ~/projects/macos/SlothyTerminal

# 3. Hand-edit two files:
#    - CHANGELOG.md   → add [VERSION] entry
#    - appcast.xml    → add <item> with BUILD_NUMBER / SIGNATURE_HERE / FILE_SIZE_IN_BYTES placeholders

# 4. Run the release pipeline (idempotent on VERSION)
./scripts/release.sh VERSION
```

`release.sh` handles version bump, build/notarize/sign, appcast substitution, commit, push, merge to `main`, and `gh release create`.
