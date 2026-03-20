# Performance Follow-up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the remaining UI stalls, stale-task races, and redundant work discovered after the terminal freeze fixes were merged.

**Architecture:** Tackle the remaining issues in priority order: harden subprocess execution, move sidebar explorer work off the main actor, dedupe terminal resize/render-path work, then tighten stale-task handling and invalidation scope. Preserve PTY lifetime semantics, keep libghostty surface calls on the main thread, and prefer extracting pure helpers only when that unlocks SwiftPM test coverage.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, libghostty, Swift Concurrency, SwiftPM tests, Xcode build verification.

---

## Constraints

- Do not use git worktrees in this repository.
- Do not destroy hidden terminal surfaces unless a replacement keepalive mechanism is already in place.
- Keep `ghostty_surface_*` calls on the main thread.
- `SlothyTerminal/Views/` and `SlothyTerminal/Terminal/` are Xcode-only; do not assume SwiftPM can test those files directly.
- If you add a new SwiftPM-covered helper outside the excluded folders, update `Package.swift`.
- Run `swift test` and `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO` before closing the work.

## Task 1: Harden subprocess execution and model loading

**Files:**
- Modify: `SlothyTerminal/Services/GitProcessRunner.swift`
- Modify: `SlothyTerminal/Services/OpenCodeCLIService.swift`
- Modify: `SlothyTerminal/Views/StartSessionContentView.swift`
- Create: `SlothyTerminalTests/GitProcessRunnerTests.swift`
- Create: `SlothyTerminalTests/OpenCodeCLIServiceTests.swift`

**Steps:**
1. Extract pure OpenCode model parsing into a small helper inside `SlothyTerminal/Services/OpenCodeCLIService.swift` so parsing, dedupe, and malformed-line behavior can be tested without launching a real process.
2. Add unit tests in `SlothyTerminalTests/OpenCodeCLIServiceTests.swift` for duplicate models, invalid rows, empty output, and sorted output order.
3. Replace the current `DispatchSemaphore` plus post-exit pipe draining in `SlothyTerminal/Services/OpenCodeCLIService.swift` with a timeout-aware async execution path that reads stdout and stderr while the child process is running.
4. Add a cancellable timeout-aware execution path to `SlothyTerminal/Services/GitProcessRunner.swift` so git subprocesses terminate and are reaped on cancel or timeout instead of blocking threads indefinitely.
5. Add focused tests in `SlothyTerminalTests/GitProcessRunnerTests.swift` for timeout, cancellation, and trimmed output behavior using a deterministic helper process.
6. Update `SlothyTerminal/Views/StartSessionContentView.swift` to call the async model loader directly from the existing `.task(id:)` path, keeping the load structured and latest-wins.

**Verification:**
- Run: `swift test --filter OpenCodeCLIServiceTests`
- Run: `swift test --filter GitProcessRunnerTests`
- Run: `swift test`

## Task 2: Move Explorer tree loading off the main actor

**Files:**
- Modify: `SlothyTerminal/Views/SidebarView.swift`
- Modify: `SlothyTerminal/Services/DirectoryTreeManager.swift`

**Steps:**
1. Replace the synchronous `loadItems()` path in `SlothyTerminal/Views/SidebarView.swift` with a cancellable task-based loader keyed by `rootDirectory`.
2. Move directory scanning and sorting in `SlothyTerminal/Services/DirectoryTreeManager.swift` onto a background-friendly async API that returns value types and publishes results back on the main actor.
3. Stop resolving icons inside view rendering by caching icons per file path or file type during tree loading instead of using `NSWorkspace.shared.icon(forFile:)` during row redraws.
4. Replace index-based tree rendering in `SlothyTerminal/Views/SidebarView.swift` with stable `FileItem.id` identity so rescan and expand operations do not recreate whole subtrees.
5. Load child directories lazily with cancellation support when a folder expands, and ignore stale results if the user collapses or switches directories before the load finishes.

**Verification:**
- Run: `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- Manual: open the Explorer sidebar in a large repo, expand several folders quickly, and confirm there is no visible hitch or row-state reset.

## Task 3: Dedupe ghostty resize work and tighten render sampling

**Files:**
- Modify: `SlothyTerminal/Terminal/GhosttySurfaceView.swift`
- Modify: `SlothyTerminal/Services/ActivityDetectionGate.swift`
- Modify: `SlothyTerminal/Terminal/GhosttyApp.swift`
- Modify: `SlothyTerminalTests/ActivityDetectionGateTests.swift`

**Steps:**
1. Cache the last framebuffer size and content scale in `SlothyTerminal/Terminal/GhosttySurfaceView.swift` and skip `ghostty_surface_set_size` and `ghostty_surface_set_content_scale` when the effective values did not change.
2. Convert background activity detection to a single in-flight latest-wins sampler so only one viewport read and one ANSI-strip task can be active at a time.
3. Keep the libghostty text read on the main thread, but skip stale scheduled reads when a newer render already superseded the pending sample.
4. Update `SlothyTerminal/Services/ActivityDetectionGate.swift` and `SlothyTerminalTests/ActivityDetectionGateTests.swift` if the gate needs versioning or in-flight tracking to support the new sampler behavior.
5. In `SlothyTerminal/Terminal/GhosttyApp.swift`, inline callback work when already on the main thread and coalesce callback-driven wakeups where possible.
6. Remove duplicate pasteboard reads on hot paths where the data is already being supplied by ghostty callbacks.

**Verification:**
- Run: `swift test --filter ActivityDetectionGateTests`
- Run: `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- Manual: resize the window repeatedly, switch tabs during active terminal output, and confirm prompt redraws and CPU spikes are reduced.

## Task 4: Make revision graph loads latest-wins

**Files:**
- Modify: `SlothyTerminal/Views/RevisionGraphView.swift`

**Steps:**
1. Add explicit task handles or generation IDs for initial load, refresh, pagination, commit details, and diff loading in `SlothyTerminal/Views/RevisionGraphView.swift`.
2. Cancel the previous task before starting a new task of the same class and ignore stale results after each awaited call.
3. Replace detached lane calculation with a cancellable path that checks cancellation before applying results.
4. Guard `loadMore()` against merging new commits into stale `allCommits` snapshots after a refresh.
5. Keep existing UI behavior the same while preventing stale inspector data from overwriting the latest selection.

**Verification:**
- Run: `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- Manual: spam refresh, scroll to trigger pagination, and switch selected commits quickly; confirm the inspector never shows stale file lists or diffs.

## Task 5: Cut redundant git work in visible UI paths

**Files:**
- Modify: `SlothyTerminal/App/AppState.swift`
- Modify: `SlothyTerminal/Views/MainView.swift`
- Modify: `SlothyTerminal/Views/GitClientView.swift`
- Modify: `SlothyTerminal/Services/GitStatsService.swift`
- Modify: `SlothyTerminalTests/GitStatsServiceTests.swift`

**Steps:**
1. Remove `isTerminalBusy` from `gitBranchRefreshContext` in `SlothyTerminal/App/AppState.swift` so the status bar no longer refreshes the branch name on every busy-idle flip.
2. Update `StatusBarView` in `SlothyTerminal/Views/MainView.swift` to refresh only on directory or tab identity changes.
3. Cache tab ordering or precomputed labels in `SlothyTerminal/App/AppState.swift` so tab-bar labels are no longer computed with repeated linear searches.
4. Reduce Git overview subprocess fan-out by batching shared repo facts inside `SlothyTerminal/Services/GitStatsService.swift` instead of recomputing overlapping git data during a single refresh.
5. Add or extend `SlothyTerminalTests/GitStatsServiceTests.swift` for any new parsing or batching helpers introduced in the service layer.

**Verification:**
- Run: `swift test --filter GitStatsServiceTests`
- Run: `swift test`
- Manual: run terminal commands in a git repo and confirm the status bar does not spawn branch refreshes on every command completion.

## Task 6: Reduce config-driven invalidation during window movement

**Files:**
- Modify: `SlothyTerminal/App/AppDelegate.swift`
- Modify: `SlothyTerminal/Services/ConfigManager.swift`
- Modify: `SlothyTerminalTests/AppConfigTests.swift`

**Steps:**
1. Move window-frame persistence out of the globally observed config mutation path or introduce a narrow persistence API that does not invalidate unrelated views on every move event.
2. Keep the debounced background-save behavior for general config writes, but prevent `didMoveNotification` from rewriting the full observable config tree repeatedly.
3. Preserve synchronous `saveImmediately()` semantics for termination.
4. Extend `SlothyTerminalTests/AppConfigTests.swift` with coverage for any new persistence helper or serialization behavior added to support the change.

**Verification:**
- Run: `swift test --filter AppConfigTests`
- Run: `swift test`
- Manual: drag the window around and confirm the UI remains responsive without repeated visible invalidation.

## Task 7: Cache external app lookups and document rows

**Files:**
- Modify: `SlothyTerminal/Services/ExternalAppManager.swift`
- Modify: `SlothyTerminal/Views/SidebarView.swift`
- Modify: `SlothyTerminal/Views/AutomationSidebarView.swift`

**Steps:**
1. Cache installed application snapshots inside `SlothyTerminal/Services/ExternalAppManager.swift` instead of recomputing `urlForApplication(withBundleIdentifier:)` on every view render.
2. Reuse cached editor lists in `SlothyTerminal/Views/SidebarView.swift` and `SlothyTerminal/Views/AutomationSidebarView.swift` instead of recalculating them in computed view properties.
3. Stop resolving document icons synchronously in row bodies where a cached icon can be reused.

**Verification:**
- Run: `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- Manual: open context menus in Project Docs and Automation sidebars repeatedly and confirm there is no stutter.

## Task 8: Re-open the still-unresolved architecture-sensitive findings

**Files:**
- Review and possibly modify: `SlothyTerminal/Views/TerminalContainerView.swift`
- Review and possibly modify: `SlothyTerminal/Views/MainView.swift`
- Review and possibly modify: `SlothyTerminal/Views/TabBarView.swift`
- Review and possibly modify: `SlothyTerminal/Terminal/GhosttySurfaceView.swift`

**Steps:**
1. Re-measure whether rendering `appState.tabs` for all workspaces in `SlothyTerminal/Views/TerminalContainerView.swift` is still required for PTY lifetime, or whether the keepalive responsibility can move into a dedicated host.
2. If the existing all-workspace ZStack is still necessary, isolate it from the visible layout so inactive workspaces do not participate in normal layout and invalidation.
3. Narrow the `GeometryReader` usage in `SlothyTerminal/Views/MainView.swift` so sidebar width tracking does not invalidate the full content tree on every resize tick.
4. Re-check `SlothyTerminal/Views/TabBarView.swift` indicator animations and replace continuous animation on hidden work with state-driven or timeline-limited animation if profiling still shows idle cost.
5. Re-check whether the remaining main-thread viewport read in `SlothyTerminal/Terminal/GhosttySurfaceView.swift` is still acceptable after the sampler work from Task 3, or whether a cheaper activity heuristic is needed.

**Verification:**
- Run: `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- Manual: test workspace switching with many tabs, hidden activity indicators, and active terminal output to confirm PTY lifetime is preserved while idle overhead drops.

## Task 9: Final verification and regression pass

**Files:**
- No source changes expected unless verification reveals a regression.

**Steps:**
1. Run the focused SwiftPM tests added or updated in Tasks 1, 3, 5, and 6.
2. Run the full SwiftPM suite.
3. Run the full Xcode debug build.
4. Manually verify the highest-risk scenarios: large repo Explorer open, repeated window resize, active terminal output, revision-graph refresh spam, workspace switching, and OpenCode model loading.
5. If profiling is available, collect one before-and-after sample for terminal output, Explorer open, and revision-graph refresh to confirm the fixes moved the right metrics.

**Verification:**
- Run: `swift test`
- Run: `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO`
