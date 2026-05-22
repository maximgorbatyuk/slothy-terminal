# Architecture

## What this is

A native macOS SwiftUI app that hosts:

- one or more **terminal surfaces** rendered by libghostty (Metal-accelerated PTY emulator)
- a **Git client** view that runs `git` as a subprocess
- a **file editor** built on STTextView with tree-sitter syntax highlighting (Swift + Markdown grammars bundled)
- a **usage stats** display that polls third-party APIs (Cursor, Anthropic) using credentials in the macOS Keychain
- an **auto-updater** that pulls a Sparkle appcast from GitHub and verifies it with an embedded EdDSA public key

There is no backend service we own. Everything runs in-process on the user's Mac except outbound HTTP to update and usage endpoints.

## Runtime boundary

```
┌──────────────────────────────────────────────────────────────────────┐
│ SlothyTerminal.app   (macOS process, not sandboxed)                  │
│                                                                      │
│   SwiftUI scene  ──►  AppState (@Observable, @MainActor, singleton)  │
│        │                  │                                          │
│        │                  ├─►  Workspaces / Tabs                     │
│        │                  ├─►  ConfigManager   (~/.config json)      │
│        │                  ├─►  InjectionOrchestrator (per-tab FIFO)  │
│        │                  └─►  UsageService   ──►  Keychain          │
│        ▼                                                             │
│   GhosttySurfaceView (NSView + NSTextInputClient)                    │
│        │                                                             │
│        ▼                                                             │
│   libghostty (C ABI, Metal renderer)                                 │
│        │                                                             │
│        ▼ PTY                                                         │
│   spawned process: claude / opencode / $SHELL                        │
└──────────────────────────────────────────────────────────────────────┘

   ▲ Sparkle (in-process)        ▲ Cursor / Anthropic dashboard APIs
   │  appcast.xml on GitHub      │  HTTPS, JWT in cookie / Bearer header
   │  EdDSA-signed DMG           │
```

The only stable native-code dependency is `GhosttyKit.xcframework` (built from the Ghostty source — see `docs/release.md`). The xcframework is not in the git tree. A fresh clone cannot build in Xcode until it is produced.

SPM-resolved dependencies pulled by the Xcode target:

- `Sparkle` — auto-updates.
- `STTextView` — text view backing the file editor (`Views/Editor/EditorTabView.swift`).
- `SwiftTreeSitter` + `SwiftTreeSitterLayer` — incremental parser bindings.
- `TreeSitterSwift`, `TreeSitterMarkdown` — bundled grammars + `queries/highlights.scm` resources consumed by `SyntaxHighlightingPlugin`.

The SPM test target intentionally excludes all of the above — see `docs/testing.md`.

## Modules

Source lives under `SlothyTerminal/`. Each subdirectory has a single responsibility:

| Directory | Purpose | Build coverage |
|---|---|---|
| `App/` | `@main` entry point (`SlothyTerminalApp`), `AppDelegate`, global `AppState`. | `AppState` — SPM. App / delegate — Xcode-only. |
| `Agents/` | `AIAgent` protocol + `TerminalAgent` / `ClaudeAgent` / `OpenCodeAgent` / `AgentFactory`. Resolves CLI paths and supplies env/args for the spawned process. | SPM. |
| `Models/` | Plain value types (`Tab`, `Workspace`, `AppConfig`, `SavedPrompt`, etc.). Domain shapes documented in `docs/domain.md`. | SPM. |
| `Services/` | Long-running app services and stateless utilities — config, git, usage, logging, file scanners, file editor I/O (`FileEditorService`). | Mixed. SPM-covered set is enumerated in `Package.swift`. UI- or Sparkle- or AppKit-bound services (`UpdateManager`, `ExternalAppManager`, `DirectoryTreeManager`, `FinderServicesProvider`) are Xcode-only. `FileEditorService` is SPM-covered. |
| `Injection/` | Per-tab FIFO queue + registry of live terminal surfaces. Used to programmatically write into a running session. See `docs/domain.md` § *Injection*. | SPM. |
| `Terminal/` | `GhosttyApp` singleton + `GhosttySurfaceView` `NSView` subclass. The libghostty C-ABI boundary lives here. | Xcode-only. |
| `Views/` | All SwiftUI views — main window, tab bar, sidebars, settings, git client, dialogs. | Xcode-only. |
| `Views/Editor/` | Editor tab — STTextView SwiftUI host, tree-sitter syntax highlighting plugin, theme palette, file menu hooks. | Xcode-only (depends on STTextView + tree-sitter SPM products that are not in the test target). |
| `Resources/` | Build-config JSON (`Config.debug.json` / `Config.release.json`), bundled fonts, third-party licences. | Bundled into the app. |

## State ownership

- **`AppState` (`App/AppState.swift`)** is `@MainActor @Observable`, instantiated once in `SlothyTerminalApp` and threaded through the SwiftUI environment. It owns the workspace list, the tab list, the active modal, the dirty-editor close state (`tabPendingDirtyEditorClose` + return-context snapshot), and the `InjectionOrchestrator`. Persistence is delegated to `ConfigManager`.
- **`ConfigManager.shared`** is the single source of truth for `AppConfig`. Mutations are written back to disk on app termination (`willTerminateNotification`) and on focus changes via `saveImmediately()`.
- **`UsageService.shared`** owns the auth-source resolution and refresh loop. Credentials are in the Keychain (`UsageKeychainStore`); see `docs/authentication.md`.
- **`InjectionOrchestrator`** is owned by `AppState` and references the `TerminalSurfaceRegistry`, which Ghostty surface views populate on attach/detach. The registry is the bridge between SwiftUI tab identity and live `NSView` surfaces.

## Concurrency model

- UI state lives on `@MainActor`. SwiftUI/AppKit does not allow otherwise.
- Subprocess and file I/O are pushed off the main actor — `GitProcessRunner` runs `git` via `Process` inside `Task.detached` with a timeout; `UsageService` makes URL requests from `Task`s and updates `@Observable` snapshots back on the main actor.
- Logging uses `OSLog` via the `Logger` extension (`Logger.app`, `Logger.pty`, `Logger.injection`, `Logger.usage`, etc. — see `Services/Logger.swift`). There is no custom logger class.

## Persistence

- **App config:** JSON, written by `ConfigManager`. Schema is the `AppConfig` Codable struct in `Models/AppConfig.swift`. Decoding is intentionally resilient — unknown / removed keys must not crash older config files. Editor-related fields (`defaultTabMode`, `editorFontName`, `editorFontSize`) follow the same `try?`-decoded pattern.
- **Saved prompts and workspaces:** persisted inside `AppConfig`.
- **Recent folders:** `RecentFoldersManager` maintains the bounded list (cap configured in `AppConfig.maxRecentFolders`).
- **Usage credentials:** macOS Keychain — service `com.slothyterminal.usage`, account `<provider>.<sourceKind>`. See `docs/authentication.md`.

## Deployment surface

- **Distribution:** signed, notarized DMG attached to a GitHub Release tag `vYYYY.M.PATCH`.
- **Auto-update:** Sparkle reads `appcast.xml` from `main` on GitHub at the URL embedded in `Info.plist` (`SUFeedURL`). Each entry is verified against the EdDSA public key (`SUPublicEDKey`).
- **Release pipeline:** `scripts/build-release.sh` and `scripts/release.sh`. Detailed steps in `docs/release.md`.
- **CI:** `.github/workflows/ci.yml` runs `swift build` + `swift test` and a lint pass on every PR to `develop` or `main`. CI does not build the Xcode target (it cannot — `GhosttyKit.xcframework` is not committed).
- **Sandboxing:** the app is not sandboxed. The user's PTY can run any binary on PATH.
