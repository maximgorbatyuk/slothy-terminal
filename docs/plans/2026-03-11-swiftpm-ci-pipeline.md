# SwiftPM CI Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a GitHub Actions pipeline that validates the Ghostty-free Swift core with `swift build` and `swift test`.

**Architecture:** Reuse the existing `SlothyTerminalLib` SwiftPM target as the CI-safe boundary. Keep Ghostty/Xcode-only files out of this lane, and strengthen documentation so future Swift code either stays testable under SwiftPM or is explicitly treated as app-only.

**Tech Stack:** SwiftPM, GitHub Actions, macOS runners, Swift 5.9+

---

### Task 1: Add GitHub Actions workflow

**Files:**
- Create: `.github/workflows/swiftpm.yml`
- Modify: `README.md`

**Step 1: Write the failing verification expectation**

Define the workflow shape and expected commands:

- checkout repository
- optionally select Xcode version
- run `swift build`
- run `swift test`

**Step 2: Run workflow-equivalent commands locally**

Run: `swift build && swift test`
Expected: PASS locally before encoding the same logic in CI.

**Step 3: Write minimal workflow**

Create `.github/workflows/swiftpm.yml` with:

- trigger on pull requests and pushes
- macOS runner
- checkout step
- SwiftPM build step
- SwiftPM test step

**Step 4: Update README briefly**

Document that GitHub CI validates the SwiftPM core only and does not build Ghostty-dependent app code.

**Step 5: Verify locally**

Run: `swift build && swift test`
Expected: PASS.

### Task 2: Document the source-boundary rule

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`

**Step 1: Add guidance for contributors**

Document:

- if code is testable and Ghostty-free, add it to `Package.swift`
- if code depends on Ghostty/AppKit terminal runtime, keep it Xcode-only
- the `sources:` list is explicit and must be updated manually

**Step 2: Keep wording concrete**

Reference existing examples such as:

- `Terminal/GhosttyApp.swift`
- `Terminal/GhosttySurfaceView.swift`
- `Views/`

**Step 3: Verify docs are consistent**

Read the updated sections and confirm they match actual package behavior.

### Task 3: Audit SwiftPM target contents

**Files:**
- Modify: `Package.swift`
- Optional: `docs/plans/2026-03-11-swiftpm-ci-boundary-design.md`

**Step 1: Review all `sources:` entries**

Check each entry in `Package.swift` and classify it:

- safe for Ghostty-free SwiftPM
- borderline, but still independent
- should move out of SwiftPM

**Step 2: Make minimal corrections if needed**

If any current source entry now depends on Ghostty/Xcode-only APIs, remove it from the package target or decouple it.

**Step 3: Run package verification**

Run: `swift build && swift test`
Expected: PASS.

### Task 4: Final verification

**Files:**
- Create: `.github/workflows/swiftpm.yml`
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `Package.swift` (if needed)

**Step 1: Run all required local checks**

Run: `swift build && swift test`
Expected: All package checks pass.

**Step 2: Confirm CI boundary is explicit**

Verify the workflow and docs clearly state that this lane does not cover Ghostty-dependent app files.

**Step 3: Optional future task note**

Document a later non-blocking lane for full Xcode app builds when Ghostty-capable CI becomes available.
