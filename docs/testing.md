# Testing

There are two build systems in this repo and only one of them runs tests. Understanding the split is the most important fact in this document.

## SwiftPM vs Xcode

| | `Package.swift` | `SlothyTerminal.xcodeproj` |
|---|---|---|
| Runs the app? | No. | Yes — this is what users get. |
| Has tests? | Yes — `SlothyTerminalTests/`. | No — none configured. |
| Links GhosttyKit? | No. | Yes. |
| Links Sparkle? | No (excluded in `Package.swift`). | Yes. |
| Discovers source files? | No — uses an explicit `sources:` list for the library target. | Yes — `PBXFileSystemSynchronizedRootGroup` auto-discovers. |
| Discovers test files? | Yes — the test target has no manual list. | n/a |
| Required for CI? | Yes — `.github/workflows/ci.yml`. | No — `GhosttyKit.xcframework` is not committed, so CI cannot build the app target. |

## Running the suite

```bash
swift test
```

Runs all tests in `SlothyTerminalTests/` against the `SlothyTerminalLib` library.

For UI changes, run an Xcode build in addition:

```bash
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

This catches missing imports, misuse of AppKit symbols, and broken `Views/` references that SPM cannot see. It does not run any tests.

## What is and isn't covered

**Covered by `swift test`:**

- `Models/` — pure value types and Codable behaviour (`AppConfig`, `Tab`, `Workspace`, `WorkspaceSplitState`, `SavedPrompt`, `MakeCommitComposerState`, `UsageModels`, …). Editor-mode tab invariants (fileURL precondition, derived title, isDirty label prefix, agentType rejection) live in `EditorTabTests.swift`.
- `Agents/` — agent type metadata, command-label parsing, launch-type behaviour.
- Most of `Services/` listed in `Package.swift` `sources:` — config, recent-folders, git process runner / parsing / lane calculation, working-tree, ANSI stripping, prompt scanners, cursor usage decoding, claude cooldown, activity gating, directory-tree expansion state (`DirectoryTreeExpansionStore` — per-root expand/collapse persistence; see `DirectoryTreeExpansionStoreTests.swift`), file editor I/O (`FileEditorService` — load/save, encoding fallbacks, binary sniff, size cap, symlink resolution; see `FileEditorServiceTests.swift`).
- `Injection/` — orchestrator queue, surface registry, request semantics. Backed by mock surfaces.
- `App/AppState` — only the parts that don't transitively depend on Views or AppKit (incl. `openFileInEditor` dedup, `canonicalFileURL`, dirty-editor close routing).

**Not covered by `swift test`:**

- Anything under `Views/` (SwiftUI views, modifiers, sidebars, settings panels), including `Views/Editor/` — STTextView, tree-sitter highlighting, and the file menu wiring are exercised manually only.
- `Terminal/GhosttyApp.swift`, `Terminal/GhosttySurfaceView.swift` — depend on the GhosttyKit binary.
- `Services/UpdateManager.swift`, `Services/ExternalAppManager.swift`, `Services/DirectoryTreeManager.swift`, `Services/FinderServicesProvider.swift` — AppKit-bound or Sparkle-bound.

If you change one of these, an Xcode build is the only check available without manual exercise.

## Adding a test

`SlothyTerminalTests/` uses XCTest. The test target auto-discovers — drop a new `*Tests.swift` file in and `swift test` picks it up. Mocks live in `SlothyTerminalTests/Mocks/`:

- `MockInjectionSurface.swift` — `InjectableSurface` stand-in for orchestrator tests.
- `MockInjectionTabProvider.swift` — `InjectionTabProvider` stand-in.

There is no shared fixture or test container. Tests are unit-level; nothing spins up a server or filesystem sandbox beyond `URL.temporaryDirectory` where a service genuinely needs a path.

## Adding a non-UI source file that should be tested

`Package.swift` uses an **explicit `sources:` list** for `SlothyTerminalLib`. A new file under `Services/`, `Models/`, `Agents/`, or `Injection/` will not be picked up by `swift test` until you add it to that list manually. Forgetting this is the single most common reason tests pass locally but the new code is not actually exercised.

Conversely, do not add files that depend on `SwiftUI`-specific environment, `AppKit`, `Sparkle`, or GhosttyKit C symbols to the `sources:` list — `swift build` will fail because those dependencies are intentionally absent from the SPM target.

## CI

`.github/workflows/ci.yml` runs on PRs targeting `develop` or `main`:

| Job | What it does |
|---|---|
| `validate` | `swift build` + `swift test` on macos-14 with Xcode 16.2's Swift toolchain. |
| `lint` | Greps `SlothyTerminal/` and `SlothyTerminalTests/` for trailing whitespace and merge-conflict markers and fails on either. |

CI does not lint Swift style, run the Xcode build, or sign anything.

## Manual smoke test

When changes touch the libghostty boundary, `Views/`, or anything Sparkle-bound, a manual smoke test is unavoidable. The minimum checklist (from `docs/release.md` § *Smoke test*) is: open a terminal tab, type and submit a command, switch input methods and confirm IME, scroll, copy/paste, open a Claude tab, close a tab, resize the window.
