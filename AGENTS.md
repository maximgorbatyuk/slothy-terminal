# AGENTS.md

> **CRITICAL CONTEXT ANCHOR**
>
> Read this block before doing anything else in this repository.
>
> 1. **This is a native macOS SwiftUI app.** Targets are: SPM library + tests (`Package.swift`) and the Xcode app target (`SlothyTerminal.xcodeproj`). The two are not interchangeable. See `docs/testing.md`.
> 2. **`Package.swift` uses an explicit `sources:` list for `SlothyTerminalLib`.** New non-UI Swift files must be added there manually or `swift build` / `swift test` will silently miss them. UI / `Views/` / Sparkle / GhosttyKit-dependent files must stay out of that list. See `docs/gotchas.md`.
> 3. **`GhosttyKit.xcframework` is gitignored and must be built from the Ghostty source.** A fresh clone cannot be built in Xcode until you produce it. See `docs/release.md` § *Updating Embedded Libghostty*.
> 4. **Do not use git worktrees for implementing features in this repo.** This is a hard project rule.
> 5. **Do not commit secrets.** `.env` (Apple notarization credentials, app-specific password) is gitignored. Sparkle EdDSA private key is not in the repo.
> 6. **Terminal sessions must set `TERM`, `COLORTERM`, `TERM_PROGRAM`, `TERM_PROGRAM_VERSION`.** Without these, shells launched from the spawned PTY mishandle escape sequences. The four agent classes that spawn processes all set these.
> 7. **Bundle identifier:** `mgorbatyuk.dev.SlothyTerminal`. App is not sandboxed (`ENABLE_APP_SANDBOX = NO`).

---

## Project overview

SlothyTerminal is a native macOS terminal application (Swift/SwiftUI) for AI coding assistants. It hosts a tabbed interface for Claude CLI, OpenCode CLI, and plain shell sessions, plus a built-in Git client. OpenCode is the primary smart backend for multi-provider model access.

- **Platform:** macOS 14.0+ (SPM platform), macOS 15.0 (Xcode deployment target)
- **Language:** Swift 5.9+
- **Build system:** Xcode 15.0+ + SwiftPM

## Where to read more

- Architecture and module layout: `docs/architecture.md`.
- Domain concepts (Workspace, Tab, Injection, lifecycle): `docs/domain.md`.
- External processes, the GhosttyKit C boundary, Sparkle appcast: `docs/interactions.md`.
- Auth (Keychain, notarization, Sparkle signing): `docs/authentication.md`.
- Test layout, what's covered, what isn't: `docs/testing.md`.
- Known traps and unresolved behaviour: `docs/gotchas.md` and `KNOWN_ISSUES.md`.
- Release process: `docs/release.md`.

## Build, test, run

```bash
# Run the app
open SlothyTerminal.xcodeproj      # then Cmd+R

# Xcode CLI build (no signing — for verifying compile without certs)
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO

# SPM core (no Ghostty, no UI) — covers agents, models, services
swift build
swift test
```

Both `xcodebuild` and `swift test` must pass after changes. CI runs the SPM build + test on `macos-14` plus a lint pass for trailing whitespace and merge-conflict markers (`.github/workflows/ci.yml`).

### Release scripts (do not run without confirmation)

```bash
# Build, notarize, create DMG (requires .env with Apple credentials)
./scripts/build-release.sh [VERSION]

# Full release: build + sign + notarize + appcast + GitHub release + DMG upload.
# Pre-requisite: appcast.xml entry with BUILD_NUMBER / SIGNATURE_HERE / FILE_SIZE_IN_BYTES
# placeholders, plus a CHANGELOG.md entry for VERSION.
./scripts/release.sh [VERSION]
```

Detailed pipeline in `docs/release.md`. The release script is destructive (pushes, merges, tags, creates a GitHub release) — do not run it as part of routine work.

## Swift style guidelines

**Use the `/developing-with-swift` skill before writing Swift code.**
**Use the `/frontend-design` skill before writing `*.html`, `*.css`, `*.js` files.**

Key rules:

- 2-space indentation, no tabs.
- `guard` clauses must be multi-line with a blank line after.
- Multi-condition `if` blocks: opening brace on its own line.
- `case` blocks followed by a blank line.
- `///` for documentation comments, `//` for inline explanatory comments and `MARK:` / `TODO:` directives.
- Use `@Observable` (not `ObservableObject`) for shared state.
- Use `async/await` and the `.task` modifier for async work; avoid Combine.
- Don't create ViewModels for every view or add unnecessary abstractions.
- Any potentially blocking operation (`Process`, network, file I/O) must be inside `Task { }` in views and marked `async` in services.
  - Example: `Task { files = await GitService.shared.getModifiedFiles(in: directory) }`

Re-read this section before opening a PR.

## Dependencies

- **GhosttyKit** (xcframework) — terminal emulation, PTY, and rendering via libghostty. Built from the Ghostty source, gitignored. See `docs/release.md` § *Updating Embedded Libghostty*.
- **Sparkle** — auto-updates. Pinned in `SlothyTerminal.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Xcode project convention

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` — it auto-discovers source files from the filesystem. **No manual `.pbxproj` edits are needed** when adding new Swift files. Only `Package.swift` requires a manual `sources:` list update for new SPM-covered non-UI files.

- If new code is intended to be part of the SPM-covered core and is SPM-compatible, add it to `Package.swift` so it stays covered by `swift build` and `swift test`.
- If new code depends on the Ghostty/AppKit terminal runtime, or is otherwise app-only, keep it Xcode-only.
- Concrete Xcode-only examples: `Terminal/GhosttyApp.swift`, `Terminal/GhosttySurfaceView.swift`, files under `Views/`, and app-only integrations such as `Services/UpdateManager.swift`.

## Terminal environment variables

Terminal sessions **must** set `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=SlothyTerminal`, and `TERM_PROGRAM_VERSION` — without these, shells launched from the spawned PTY mishandle escape sequences (cursor, colours, line clearing).

Set in: `TerminalView.makeLaunchEnvironment()`, `TerminalAgent.environmentVariables`, `ClaudeAgent.environmentVariables`, `OpenCodeAgent.environmentVariables`.

## Things to never do without explicit confirmation

- Push, force-push, or run `./scripts/release.sh`.
- Edit `appcast.xml` directly outside the release flow.
- Change `Info.plist`'s `SUPublicEDKey` or `SUFeedURL`.
- Modify `GhosttyKit.xcframework` contents.
- Add UI / Sparkle / GhosttyKit-dependent files to the `Package.swift` `sources:` list.

## Things to do every time you finish work

- `swift test` for any change touching the SPM-covered core.
- An Xcode build (or at minimum the `xcodebuild` CLI command above) for any change touching `Views/`, `Terminal/`, or app-only services.
- Re-read § *Swift style guidelines* above before opening a PR.
