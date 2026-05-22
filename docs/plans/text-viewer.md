# Text Viewer / Editor Tab — Integration Plan

## Goal

Add a native code editor inside SlothyTerminal so the user can double-click a file in the sidebar Folder view and have it open in a new tab with read/write/save/undo/redo support.

The editor must support:

- opening any text file from the Folder view via double-click
- displaying line numbers, monospaced font, and macOS light/dark theming
- editing with native `NSUndoManager`-backed Undo (Cmd+Z) and Redo (Cmd+Shift+Z)
- saving (Cmd+S) and Save As (Cmd+Shift+S)
- a dirty indicator on the tab title and a Save / Don't Save / Cancel prompt on close
- syntax highlighting for Swift, JSON, Markdown, YAML, Bash, HTML in v1
- restoring open editor tabs across app launches

## Product Decisions

- Underlying editor: **STTextView** (`https://github.com/krzyzanowskim/STTextView`), TextKit 2 based, native AppKit.
- Licensing: project is or will be made GPL v3 compatible; STTextView's GPL v3 license is accepted.
- Syntax highlighting ships in v1 via **STTextView-Neon** plugin + tree-sitter grammars for Swift, JSON, Markdown, YAML, Bash, HTML. Unknown extensions render as plain text.
- Double-clicking a file already open in an editor tab focuses the existing tab — never duplicates.
- Editor tabs persist across launches via the existing `Tab` `Codable` flow. If the file no longer exists on restore, the tab opens to a non-fatal error state.
- File size guard: files larger than 10 MB show an "Open anyway?" prompt instead of auto-loading.
- Binary files (NUL bytes detected in the first 8 KB) are refused with a clear error message.
- The `NSViewRepresentable` wrapper and all editor views live in the Xcode-only app target. Only the file I/O service is added to `Package.swift` sources.
- Cmd+Z / Cmd+Shift+Z are **not** wired globally — `STTextView` rides the AppKit responder chain and `NSUndoManager` for free when the editor has first-responder focus.

## Current Constraints

- [Tab.swift](/Users/maximgorbatyuk/projects/macos/SlothyTerminal/SlothyTerminal/Models/Tab.swift) `TabMode` currently has only `.terminal` and `.git` — no editor mode.
- [AppState.swift](/Users/maximgorbatyuk/projects/macos/SlothyTerminal/SlothyTerminal/App/AppState.swift) tab-creation helpers (`createTab`, `createGitTab`) at lines 357 and 391 are agent/terminal centric; no editor entry point exists.
- [TerminalContainerView.swift](/Users/maximgorbatyuk/projects/macos/SlothyTerminal/SlothyTerminal/Views/TerminalContainerView.swift) routes tabs by mode around line 186 — `.editor` would fall through to the terminal branch today.
- [SidebarView.swift](/Users/maximgorbatyuk/projects/macos/SlothyTerminal/SlothyTerminal/Views/SidebarView.swift) `FileItemRow` line 234 currently copies the file path to clipboard on double-click. This behavior moves to the right-click context menu so it is not lost.
- `Package.swift` uses an explicit `sources:` list — only the new file I/O service is added there; views and the `NSViewRepresentable` wrapper stay Xcode-only per AGENTS.md.
- The Xcode app target adds Sparkle as an SPM dependency via the project, not via `Package.swift`. STTextView and Neon follow the same pattern.
- There is no centralized Save/Undo/Redo command system in `SlothyTerminalApp.swift` today — a new `CommandMenu("File")` group is introduced.
- Old config payloads must keep deserializing — `Tab`'s `Codable` implementation must decode missing `fileURL` / `isDirty` as defaults (same resilience pattern used after the Chat removal).

## Recommended Approach

Implement a thin SwiftUI wrapper around `STTextView`, route a new `TabMode.editor` case through the existing tab system, and centralize all file I/O in an SPM-covered service.

The implementation introduces:

- `TabMode.editor` plus `fileURL: URL?` and `isDirty: Bool` on `Tab`.
- A `FileEditorService` in `Services/` covered by `swift test`.
- An `EditorTabView` SwiftUI container that owns load state and the text binding.
- An `STTextEditorView: NSViewRepresentable` modeled on `Terminal/GhosttySurfaceView.swift`.
- A `CommandMenu("File")` group in `SlothyTerminalApp.swift` that publishes Save / Save As / Revert through `@FocusedValue`.

## Implementation Steps

### Step 1 — Add SPM dependencies to the Xcode project

In `SlothyTerminal.xcodeproj`, File → Add Package Dependencies:

- `https://github.com/krzyzanowskim/STTextView` — products `STTextView`, `STTextViewUI` (SwiftUI integration), `STTextViewSwiftUI`.
- `https://github.com/krzyzanowskim/STTextView-Neon` — Neon plugin bridge.
- `https://github.com/ChimeHQ/Neon` — pulled transitively, declare explicitly for clarity.
- `https://github.com/ChimeHQ/SwiftTreeSitter` — transitive.
- Tree-sitter grammar packages, one each: `tree-sitter-swift`, `tree-sitter-json`, `tree-sitter-markdown`, `tree-sitter-yaml`, `tree-sitter-bash`, `tree-sitter-html`.

All added to the `SlothyTerminal` app target only. `Package.swift` is **not** modified — these packages are app-only because they back the SwiftUI/AppKit editor view, which is Xcode-only.

### Step 2 — Extend the Tab model

`Models/Tab.swift`:

- Add `case editor` to `TabMode`.
- Add to `Tab`:
  - `var fileURL: URL?` — populated for `.editor` mode, `nil` for `.terminal` / `.git`.
  - `var isDirty: Bool = false`.
  - `var displayName: String` — computed: `fileURL?.lastPathComponent ?? workingDirectory.lastPathComponent`.
- Implement `Codable` with default-on-missing for `fileURL` and `isDirty` so old serialized tabs keep decoding.
- Unit-test the `Codable` round-trip and an old-payload-without-fileURL decode in `SlothyTerminalTests`.

### Step 3 — File I/O service (SPM-covered)

`Services/FileEditorService.swift`, added to the `Package.swift` `sources:` list for `SlothyTerminalLib`.

API:

- `func load(_ url: URL) async throws -> (text: String, encoding: String.Encoding)` — try UTF-8, then fall back to a small encoding list, throw `EditorError.binaryFile` if all fail.
- `func save(_ text: String, to url: URL, encoding: String.Encoding) async throws` — write `.atomic`, preserve original encoding.
- `func isProbablyBinary(_ url: URL) async -> Bool` — sniff the first 8 KB for NUL bytes.
- `static let maxInlineSize: Int = 10 * 1024 * 1024`.

All file work runs off the main thread via `async` (AGENTS.md: blocking ops inside `Task { }` or `async`).

Tests cover UTF-8 round-trip, binary refusal, size-threshold boundary, and a non-UTF-8 fallback decode.

### Step 4 — STTextView SwiftUI bridge

`Views/Editor/STTextEditorView.swift`, Xcode-only.

- `NSViewRepresentable` wrapping `STTextView.STTextView`, structured like `Terminal/GhosttySurfaceView.swift` (init, `makeNSView`, `updateNSView`, `Coordinator`).
- Coordinator owns:
  - `NSUndoManager` (free Cmd+Z / Cmd+Shift+Z).
  - Throttled change callback → updates `Tab.isDirty = (currentText != lastSavedText)`.
  - A `save()` closure invoked by the menu via `FocusedValue`.
- Configuration on `makeNSView`:
  - Monospaced font (`SF Mono`, size from `AppConfig` if available, else 13pt).
  - Line numbers gutter on.
  - Soft-wrap off.
  - Theme tracks `colorScheme`.

#### Step 4a — Neon plugin and language map

`Views/Editor/EditorLanguage.swift`:

- Enum that maps a file extension to `{ Language, HighlightsQuery }` for the six v1 grammars.
- Unknown extensions return `nil` → plain text path.

`STTextEditorView.Coordinator`:

- Installs the Neon plugin with the resolved language on first load.
- Swaps grammar if the underlying `fileURL` changes.

`Views/Editor/EditorTheme.swift`:

- Small struct mapping Neon highlight names (`keyword`, `string`, `comment`, `function`, etc.) to `NSColor`.
- Two presets: `light` and `dark`. Selected by `colorScheme`.

#### Step 4b — Grammar wiring sanity test

`SlothyTerminalTests/EditorLanguageTests.swift`:

- Smallest possible test that loads tree-sitter-json, parses `{"a":1}`, asserts a non-nil root node.
- Catches vendored `.a` linking failures on first SPM resolve before manual testing.

### Step 5 — Editor tab container

`Views/Editor/EditorTabView.swift`, Xcode-only.

State:

- `text: String`
- `loadState: .loading | .ready | .error(EditorError) | .tooLarge | .missing`
- `encoding: String.Encoding`

Behavior:

- `.task(id: tab.fileURL)` loads via `FileEditorService`.
- Renders `STTextEditorView(text: $text, language: ...)` when `.ready`.
- Renders simple error / large-file / missing-file views otherwise.
- Exposes a `save()` closure through `@FocusedValue(\.editorSave)` so the menu can reach the focused editor.

### Step 6 — Wire double-click in the Folder view

`Views/SidebarView.swift`, `FileItemRow` around line 234:

- Replace the `.onTapGesture(count: 2) { copyToClipboard(...) }` body so that for non-directory items it calls `appState.openFileInEditor(item.url)`. Directories keep the existing expand-on-double-click behavior.
- Move "Copy path" into the existing right-click context menu so the previous capability stays available.

### Step 7 — AppState additions

`App/AppState.swift`:

- `func openFileInEditor(_ url: URL)`:
  - If a `.editor` tab with the same `fileURL` exists → `switchToTab(id:)`, return.
  - Else build a `Tab(mode: .editor, fileURL: url, workingDirectory: url.deletingLastPathComponent(), ...)`, append, set active.
- Modify `closeTab(id:)`: if the tab is `.editor` and `isDirty`, show an `NSAlert` with Save / Don't Save / Cancel before removing.
- Restore path: when rebuilding tabs from config, an `.editor` tab whose `fileURL` no longer exists is kept and surfaces as `.missing` in the view — never silently dropped.

### Step 8 — Route the new tab

`Views/TerminalContainerView.swift` around line 186:

In the existing `if tab.mode == .git { ... } else if ...` chain, add:

```swift
} else if tab.mode == .editor {
  EditorTabView(tab: tab)
}
```

placed before the terminal branch.

### Step 9 — Commands menu

`App/SlothyTerminalApp.swift`:

New `CommandMenu("File")` group:

- "Save" — Cmd+S — enabled iff the active tab is `.editor` and dirty; calls the focused `save()` closure.
- "Save As…" — Cmd+Shift+S — `NSSavePanel`, then re-target `tab.fileURL` and save.
- "Revert to Saved" — no shortcut — reloads the file from disk after confirmation if dirty.

Cmd+Z / Cmd+Shift+Z are intentionally not added — the responder chain handles them.

### Step 10 — Verification

Automated:

- `swift test` — `FileEditorService` unit tests, `Tab` `Codable` round-trip, `EditorLanguage` tree-sitter-json smoke test.
- `xcodebuild` clean build.

Manual:

- Double-click a `.swift` file → opens, highlights, edits, Cmd+S saves, dirty dot appears and clears.
- Cmd+Z / Cmd+Shift+Z across word boundaries.
- Close with unsaved changes → Save / Don't Save / Cancel prompt.
- Double-click the same file again → focuses the existing tab, no duplicate.
- Open `.swift`, `.json`, `.md`, `.yaml`, `.sh`, `.html`, and a `.txt` — first six show colored tokens, `.txt` is plain.
- Toggle light/dark — colors update.
- Open a > 10 MB file → "Open anyway?" prompt.
- Open a `.png` or compiled binary → refused with binary-file error.
- Relaunch with a previously open `.editor` tab whose file has been deleted → tab restores to missing-file state, app does not crash.

Re-read AGENTS.md § *Swift style guidelines* before opening the PR.

## Out of Scope (v2 candidates)

- Per-theme customization beyond the bundled light/dark presets.
- Additional grammars beyond the v1 six.
- File-on-disk change watcher with reload-on-conflict UX.
- Multi-cursor / advanced editing features beyond STTextView's defaults.
- Find / Replace UI inside the editor pane (STTextView ships find natively — wiring a SwiftUI affordance is a follow-up).
- Encoding picker UI (v1 detects and preserves; user can't override).
