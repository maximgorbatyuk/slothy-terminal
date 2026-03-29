# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SlothyTerminal is a native macOS terminal application (Swift/SwiftUI) for AI coding assistants. It features a tabbed interface supporting Claude CLI, OpenCode CLI, and plain terminal sessions with real-time session statistics. OpenCode is the primary smart backend for multi-provider model access.

- **Platform:** macOS 14.0+ (SPM), macOS 15.0 (Xcode deployment target)
- **Language:** Swift 5.9+
- **Build System:** Xcode 15.0+ with SPM

## Repository rules

- Do not use git worktrees for implementing features.

## Build Commands

```bash
# Open in Xcode (then Cmd+R to build/run)
open SlothyTerminal.xcodeproj

# Xcode CLI build (no signing — for verification without certs)
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO

# SPM build & test (agents, models, services — no UI)
swift build
swift test
# NOTE: Package.swift uses an explicit `sources:` list for the main library target (SlothyTerminalLib).
# If new code is intended to be part of the SwiftPM-covered core and is SwiftPM-compatible, add it to that list manually or swift build/test will fail.
# If code depends on the Ghostty/AppKit terminal runtime, or is otherwise app-only, keep it Xcode-only and out of Package.swift.
# The test target auto-discovers files — no manual list needed for new tests.

# Release build with notarization (requires .env with Apple credentials)
./scripts/build-release.sh [VERSION]
# Example: ./scripts/build-release.sh 2026.2.2

# Full release: build + sign + notarize + update appcast + GitHub release + upload DMG
# Requires: .env, sparkle-tools/bin/sign_update, gh CLI authenticated
# Pre-requisite: appcast.xml entry (with BUILD_NUMBER/SIGNATURE_HERE/FILE_SIZE_IN_BYTES placeholders) and CHANGELOG.md entry for VERSION must exist before running
./scripts/release.sh [VERSION]
# Example: ./scripts/release.sh 2026.2.15
#
# Release workflow:
#   1. Write CHANGELOG.md entry for the new version
#   2. Add appcast.xml <item> with SIGNATURE_HERE and FILE_SIZE_IN_BYTES placeholders
#   3. Use BUILD_NUMBER placeholder for sparkle:version in the new appcast entry (auto-incremented by script)
#   4. Run ./scripts/release.sh VERSION
#   The script handles: Xcode version bump, build number increment, build, notarize, Sparkle sign, appcast update, commit, GitHub release, push, merge to main
```

## Compact Instructions

When compressing, preserve in priority order:
- Architecture decisions (NEVER summarize)
- Modified files and their key changes
- Current verification status (pass/fail)
- Open TODOs and rollback notes
- Tool outputs (can delete, keep pass/fail only)

## Swift Style Guidelines

**Use the `/developing-with-swift` skill before writing Swift code.**
**Use the `/frontend-design` skill before writing *.html, *.css, *.js files.**

Key rules:

- 2 spaces indentation, no tabs
- `guard` clauses must be multi-line with blank line after
- Multi-condition `if` blocks: opening brace on own line
- `case` blocks followed by blank line
- Use `///` for documentation comments, `//` for inline explanatory comments and MARK/TODO directives
- Use `@Observable` (not ObservableObject) for shared state
- Use `async/await` and `.task` modifier for async work; avoid Combine
- Don't create ViewModels for every view or add unnecessary abstractions
- Any potentially blocking operations (Process, network, file I/O) must be called within `Task { }` in views and marked `async` in services
  - Example: `Task { files = await GitService.shared.getModifiedFiles(in: directory) }`

## Dependencies

- **GhosttyKit** (xcframework) - Terminal emulation, PTY, and rendering via libghostty (built from source, gitignored)
- **Sparkle** (2.8.1) - Automatic updates framework

## Xcode Project Convention

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` — it auto-discovers source files from the filesystem. **No manual `.pbxproj` edits are needed** when adding new Swift files. Only `Package.swift` requires manual source list updates for new SwiftPM-covered non-UI files.

- If new code is intended to be part of the SwiftPM-covered core and is SwiftPM-compatible, add it to `Package.swift` so it stays covered by `swift build` and `swift test`.
- If new code depends on the Ghostty/AppKit terminal runtime, or is otherwise app-only, keep it Xcode-only.
- Concrete Xcode-only examples: `Terminal/GhosttyApp.swift`, `Terminal/GhosttySurfaceView.swift`, files under `Views/`, and app-only integrations such as `Services/UpdateManager.swift`.
- `Package.swift` uses an explicit `sources:` list for `SlothyTerminalLib`, so new SwiftPM-covered non-UI files must be added there manually.

## Terminal Environment Variables

Terminal sessions **must** set `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=SlothyTerminal`, and `TERM_PROGRAM_VERSION` — without these, shells launched from Finder mishandle escape sequences (cursor, colors, line clearing).

Set in: `TerminalView.makeLaunchEnvironment()`, `TerminalAgent.environmentVariables`, `ClaudeAgent.environmentVariables`, `OpenCodeAgent.environmentVariables`.


## Testing

```bash
swift test    # Runs all SPM tests (agents, models, services)
```

- **SPM-testable**: Everything in `Package.swift` `sources:` list — models, services, agents
- **UI-only** (Xcode only): Views, GhosttyApp, GhosttySurfaceView, UpdateManager, ExternalAppManager
- Test target auto-discovers files in `SlothyTerminalTests/` — no manual list needed for new tests
