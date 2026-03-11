# Ghostty-Free SwiftPM CI Boundary Design

## Goal

Set up a GitHub CI pipeline that validates Swift code for the Ghostty-independent core of the app without requiring `GhosttyKit` or a full Xcode app build.

## Current State

The repository already has a partial separation:

- `Package.swift` defines `SlothyTerminalLib` as a SwiftPM target for testable core code.
- `Package.swift` explicitly excludes `SlothyTerminal/Views`, `SlothyTerminal/Terminal/GhosttyApp.swift`, and `SlothyTerminal/Terminal/GhosttySurfaceView.swift`.
- `swift build` and `swift test` already work without linking Ghostty.

This means the main problem is CI enforcement and maintainability, not an initial architecture split.

## Recommended Approach

Use the existing SwiftPM target as the official Ghostty-free CI boundary.

GitHub Actions should run only:

- `swift build`
- `swift test`

on the `SlothyTerminalLib` package target.

This gives reliable regression coverage for models, services, chat engine, parsers, Telegram runtime, injection core, and app state without depending on `GhosttyKit` or app bundling.

## Scope

### In Scope

- GitHub Actions workflow for SwiftPM build and tests
- Documentation for what belongs inside the SwiftPM boundary
- Audit of the explicit `Package.swift` source list to keep Ghostty-free coverage accurate

### Out of Scope

- Full Xcode app build in CI
- Ghostty runtime integration checks in GitHub CI
- Source-tree modularization into multiple packages as a first step

## Risks

### Explicit source list drift

`Package.swift` uses an explicit `sources:` list. New testable files can be silently omitted unless contributors update it.

### Borderline dependencies

Some non-UI files may be conceptually close to terminal runtime. They must remain Ghostty-free if they stay inside the SwiftPM target.

## Mitigations

- Document the SwiftPM/Xcode boundary clearly.
- Treat `swift build` and `swift test` as required PR checks.
- Add a follow-up audit or helper script later to detect source-list drift.

## Rollout

1. Add `.github/workflows/swiftpm.yml` for macOS SwiftPM validation.
2. Update project docs with the SwiftPM boundary rule.
3. Audit `Package.swift` source entries for accidental Ghostty coupling.
4. Optionally add a future Xcode lane when Ghostty-capable CI becomes practical.
