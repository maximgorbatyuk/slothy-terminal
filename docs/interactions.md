# Interactions

Everything the app talks to that lives outside its own process. There is no first-party backend.

## libghostty (in-process, C ABI)

The terminal-rendering boundary. Both directions go through `GhosttyKit.xcframework`.

- **Outbound (Swift → C):** `Terminal/GhosttySurfaceView.swift` calls `ghostty_surface_*` for keyboard, mouse, paste, IME-point queries, size changes, and teardown. `Terminal/GhosttyApp.swift` calls `ghostty_app_new` / `ghostty_config_*` for global setup.
- **Inbound (C → Swift):** libghostty calls back into Swift trampolines registered in `ghostty_runtime_config_s` for clipboard read/write, action dispatch (window resize, title change, etc.), and surface events. Userdata pointers round-trip via `Unmanaged<GhosttySurfaceView>.fromOpaque`.

The xcframework is not in the repo. See `docs/release.md` § *Updating Embedded Libghostty* for build steps and what to check when the C ABI changes.

## STTextView + tree-sitter (in-process, SPM dependencies)

The file editor (`Views/Editor/`) is backed by two SPM packages resolved into the Xcode target:

- **STTextView** — AppKit text view exposed to SwiftUI via `STTextViewSwiftUI.TextView`. Drives the line numbers, line highlight, and wrapping. Plugin API is **add-only** — `SyntaxHighlightingPlugin` is installed once at first `makeNSView` and never replaced; language / theme changes mutate the coordinator in place. See `docs/gotchas.md`.
- **SwiftTreeSitter** + bundled grammars (`TreeSitterSwift`, `TreeSitterMarkdown`) — used for capture-driven syntax highlighting. `EditorLanguage.loadHighlightsQuery()` resolves the per-grammar `queries/highlights.scm` resource from the SPM-generated bundle and feeds it to `Query` for rendering. The bundle-name match uses an exact suffix so `TreeSitterMarkdownInline` doesn't shadow `TreeSitterMarkdown`.

Both dependencies are intentionally absent from the SPM test target — only the Xcode target links them.

## Spawned subprocesses

| Process | Spawned by | Purpose | Notes |
|---|---|---|---|
| `claude` | `Agents/ClaudeAgent.swift` via libghostty PTY | Claude CLI / TUI session | Path resolution prefers Mach-O over Node wrapper; `ANTHROPIC_API_KEY` forwarded if present in app env. |
| `opencode` | `Agents/OpenCodeAgent.swift` via libghostty PTY | OpenCode CLI / TUI session | Honours `OPENCODE_PATH`, otherwise PATH lookup. Initial prompts use `--prompt`, not `--`. |
| `$SHELL` (default `/bin/zsh`) | `Agents/TerminalAgent.swift` via libghostty PTY | Plain shell | Used as a host for Claude/OpenCode tabs too (see `AgentType.needsShellHost`). |
| `git` | `Services/GitProcessRunner.swift` via `Process` (not a PTY) | Repo operations powering the Git client view | Stdout / stderr captured, default 30s timeout, run inside `Task.detached`. Used by `GitService`, `GitStatsService`, `GitWorkingTreeService`. |
| Python scripts | `Services/PythonScriptScanner.swift` | Discover repo-local Python helpers for the prompts UI | Read-only filesystem scan; nothing executed. |

All four agent classes (terminal/claude/opencode plus `TerminalView.makeLaunchEnvironment`) inject the required `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=SlothyTerminal`, `TERM_PROGRAM_VERSION` environment variables. Without them, shells launched from the app mishandle escape sequences. See `docs/gotchas.md`.

## Outbound HTTP

| Endpoint | Caller | Purpose | Auth |
|---|---|---|---|
| `https://raw.githubusercontent.com/maximgorbatyuk/slothy-terminal/main/appcast.xml` | Sparkle (in-process), URL set as `SUFeedURL` in `Info.plist` | Auto-update feed | EdDSA signature on each enclosure verified against `SUPublicEDKey`. |
| Cursor dashboard endpoints (`/api/dashboard/get-filtered-usage-events`, `/api/dashboard/get-current-period-usage`) | `Services/CursorUsageProvider.swift` | Per-event and aggregated usage for the Cursor stats popover | `WorkosCursorSessionToken` cookie composed from a userID + JWT (the JWT is read from Cursor.app's SQLite state DB or the Keychain). |
| Other AI-provider usage endpoints | provider-specific files in `Services/` | Token / spend snapshots for `claude`, `codex`, `opencode` | Credentials per provider, all stored via `UsageKeychainStore`. See `docs/authentication.md`. |
| GitHub Releases | `gh` CLI invoked from `scripts/release.sh` (build-time only) | Create release, upload DMG | The user's `gh auth login` session. |
| Apple notarization service | `xcrun notarytool` invoked from `scripts/build-release.sh` (build-time only) | Sign + staple the DMG | `.env` Apple ID + app-specific password, stored in a Keychain notarization profile. |

There is no telemetry, analytics, or crash-reporting endpoint. The app does not phone home outside the four cases above.

## OS integration

| Mechanism | Code | Purpose |
|---|---|---|
| `NSServices` (Finder Services menu) | `Info.plist` declares two services; selectors live in `Services/FinderServicesProvider.swift`; cold-launch requests are queued in `Services/FinderServiceRequestQueue.swift` and drained when the SwiftUI scene appears. | Right-click a folder in Finder → *New SlothyTerminal Tab Here* / *…Window Here*. |
| `NSWorkspace.urlForApplication(withBundleIdentifier:)` | `Services/ExternalAppManager.swift` | Detects installed editors (VS Code, Cursor, Xcode, JetBrains, Sublime, BBEdit, Nova, etc.) and surfaces the *Open in…* menu in the title bar. |
| Drag-and-drop | various `Views/` files | Workspace reordering, file paths into prompts. |
| Bundled fonts | `Resources/Fonts/`, registered at launch by `AppDelegate.assertBundledFontsRegistered()` | Custom UI font option. `ATSApplicationFontsPath` quirk documented inline in `Info.plist` — do not change to `"Fonts"`. |
| Sparkle | `Services/UpdateManager.swift` | Wraps `SPUStandardUpdaterController` and exposes the *Check for Updates…* menu item. |

## Filesystem touchpoints

- `~/.config/ghostty/config` — read by libghostty for terminal customization. The app does not write there.
- `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` — Cursor.app's SQLite token store, read by `CursorUsageProvider` if the user picks auto-detect.
- `~/Library/Preferences/<bundle id>.plist` — `UserDefaults` storage used by Sparkle and by `ConfigManager` for the JSON config blob.
- macOS Keychain — service `com.slothyterminal.usage` (see `docs/authentication.md`).
- Arbitrary user files via the editor — `FileEditorService` reads and writes whatever path the user double-clicks in the Files sidebar or saves to. Writes are atomic and follow symlinks so a symlinked dotfile stays linked. Reads enforce a 10 MB cap and a NUL-byte binary sniff before decoding.

## What this section is not

There are no inbound webhooks, message queues, scheduled jobs, or background daemons. There is no event bus other than `NotificationCenter` and SwiftUI's own observation. Cross-component messaging that you'd reach for an event bus to express in a server app is, in this codebase, a method on `AppState` or an `@Observable` change.
