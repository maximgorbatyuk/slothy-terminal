# Terminal Surface Freeze — Root Cause Analysis & Fix Plan

**Date:** 2026-03-19

## Root Causes (Why the Terminal Freezes)

The primary freeze vector is a **cascading main-thread blockage** during heavy terminal output:

1. **Every render event queues main-thread work** — Each `GHOSTTY_ACTION_RENDER` callback schedules a `DispatchQueue.main.asyncAfter` for activity detection. During rapid output (e.g., `cat` a large file), hundreds of these pile up per second, starving the main run loop.

2. **Each queued item does a synchronous viewport read** — `readViewportText()` calls `ghostty_surface_size()` + `ghostty_surface_read_text()` — blocking C calls on the main thread that can take 50–200ms for a full terminal buffer.

3. **Infinite animations consume frame budget** — `BackgroundActivityIndicator` and `ExecutingIndicator` use `.repeatForever` even on hidden tabs. With 5+ tabs, these eat into the already-starved main thread.

4. **Four independent timers fire on the main run loop** — Three 1-second sidebar timers + one 0.4s streaming indicator timer, each triggering view re-renders.

5. **All tabs rendered in ZStack regardless of workspace** — `TerminalContainerView.singleLayout` iterates `appState.tabs` (all workspaces), not `visibleTabs`. Hidden tabs still instantiate views and run `.task` blocks.

6. **ConfigManager.save() blocks main thread on fsync** — Timer-based save callback runs `JSONEncoder.encode()` + `Data.write(options: .atomic)` on the main thread.

---

## Findings Summary

| Tier | # | Finding | File | Impact |
|------|---|---------|------|--------|
| **CRITICAL** | 1 | Activity detection `asyncAfter` pile-up during rapid output | `GhosttySurfaceView.swift:1199` | Hard freeze during heavy output |
| **CRITICAL** | 2 | Synchronous `ghostty_surface_read_text()` on main thread | `GhosttySurfaceView.swift:1168` | 50–200ms block per read |
| **CRITICAL** | 3 | `.repeatForever` animations on hidden tabs | `TabBarView.swift:401,424` | Continuous main-thread animation work |
| **CRITICAL** | 4 | 3× `Timer.publish(every:1)` + 1× `Timer.publish(every:0.4)` on main run loop | `SidebarView.swift:66,108,737` / `MessageBubbleView.swift:260` | Constant re-renders at idle |
| **HIGH** | 5 | ZStack renders ALL tabs, not visible workspace tabs | `TerminalContainerView.swift:37` | O(n) view instantiation per workspace switch |
| **HIGH** | 6 | `ConfigManager.save()` JSON+fsync on main thread | `ConfigManager.swift:107` | Freeze during settings changes |
| **HIGH** | 7 | `ChatSessionStore.loadSnapshot()` sync file I/O in init | `ChatSessionStore.swift:102` | Freeze when restoring chat tabs |
| **HIGH** | 8 | `StatsParser` compiles fresh `NSRegularExpression` per call (8+ times) | `StatsParser.swift:112+` | 10–50× slower than cached regex |
| **HIGH** | 9 | `NSPasteboard` in C callback trampolines | `GhosttyApp.swift:375` | 10–500ms block on paste/copy |
| **HIGH** | 10 | `GeometryReader` in MainView invalidates entire tree on sidebar drag | `MainView.swift:27` | Jank during sidebar resize |
| **HIGH** | 11 | Chat auto-scroll bypasses throttle on message count change | `ChatMessageListView.swift:49` | Layout thrash during streaming |
| **MEDIUM** | 12 | `tabBarLabel(for:)` is O(n²) in tab count | `AppState.swift:122` | Sluggish tab switching with 10+ tabs |
| **MEDIUM** | 13 | `MarkdownBlockParser.parse()` called in `body` | `MarkdownRendererView.swift:16` | Re-parsed on every parent re-render |
| **MEDIUM** | 14 | Tool maps computed in `MessageBubbleView.body` | `MessageBubbleView.swift:11` | Redundant iteration per render |
| **MEDIUM** | 15 | `resolveClaudePath()` / `resolveOpenCodePath()` blocks on `which` subprocess | `ClaudeCLITransport.swift:314` | 100ms+ delay on first chat start |
| **MEDIUM** | 16 | `DispatchQueue.main.async` hops in C callbacks even when already on main | `GhosttyApp.swift:195+` | Queue congestion during high-frequency events |

---

## Fix Plan

### Phase 1: Eliminate the Freeze Loop (CRITICAL — highest ROI)

| Step | Fix | File(s) | Effort |
|------|-----|---------|--------|
| **1a** | **Throttle activity detection** — Replace per-render `asyncAfter` with a single coalescing mechanism (e.g., a `Bool` flag + one scheduled check). Cancel pending work item before scheduling new one. | `GhosttySurfaceView.swift` | Medium |
| **1b** | **Move viewport read off main thread** — Keep `ghostty_surface_read_text()` on main (required by libghostty), but wrap in a single-shot `DispatchQueue.main.async` that checks a dirty flag, preventing pile-up. Post-processing (ANSI strip, diff) stays on background. | `GhosttySurfaceView.swift` | Medium |
| **1c** | **Disable animations on hidden tabs** — Gate `.repeatForever` on `isVisible` binding. When tab is not active, set `isPulsing = false`. | `TabBarView.swift` | Low |
| **1d** | **Consolidate sidebar timers** — Replace 3 independent `Timer.publish` with a single shared timer or use `TimelineView(.periodic(every: 1))`. | `SidebarView.swift` | Low |

### Phase 2: Reduce View Invalidation Scope (HIGH)

| Step | Fix | File(s) | Effort |
|------|-----|---------|--------|
| **2a** | **Filter ZStack to visible workspace tabs** — Change `ForEach(appState.tabs)` → `ForEach(appState.visibleTabs)` in `singleLayout` and `splitLayout`. | `TerminalContainerView.swift` | Low |
| **2b** | **Move ConfigManager.save() to background queue** — Dispatch JSON encoding + `Data.write` to a serial utility queue. Keep `saveImmediately()` synchronous for app termination. | `ConfigManager.swift` | Low |
| **2c** | **Make `loadSnapshot()` async** — Move `Data(contentsOf:)` + decode to background, call from `.task` instead of `init`. | `ChatSessionStore.swift` | Medium |
| **2d** | **Cache compiled regexes in StatsParser** — Use `static let` for all `NSRegularExpression` instances. | `StatsParser.swift` | Low |

### Phase 3: Polish & Remaining Issues (HIGH/MEDIUM)

| Step | Fix | File(s) | Effort |
|------|-----|---------|--------|
| **3a** | **Defer clipboard ops in C callbacks** — Dispatch `NSPasteboard` reads to main async to avoid blocking the C callback return. | `GhosttyApp.swift` | Low |
| **3b** | **Throttle chat auto-scroll uniformly** — Apply the 0.1s throttle to *both* `onChange` triggers (message count + text). | `ChatMessageListView.swift` | Low |
| **3c** | **Cache `tabBarLabel` results** — Precompute labels when `visibleTabs` changes, store in dictionary. | `AppState.swift` / `TabBarView.swift` | Low |
| **3d** | **Cache parsed markdown** — Store `MarkdownBlockParser.parse()` result in `@State` and recompute only when `text` changes. | `MarkdownRendererView.swift` | Low |
| **3e** | **Minimize GeometryReader scope** — Move `GeometryReader` to wrap only the sidebar resize handle, not the entire MainView. | `MainView.swift` | Medium |

---

## Expected Impact

- **Phase 1** alone should eliminate the hard freeze during rapid terminal output — that's the primary complaint.
- **Phase 2** reduces baseline CPU usage and eliminates jank during tab switching and settings changes.
- **Phase 3** polishes remaining rough edges for a smooth experience at scale (10+ tabs, long chat sessions).

## Architecture Constraints

These constraints MUST be respected during fixes:

- **PTY lifecycle is tied to SwiftUI view hierarchy.** Terminal tabs use a ZStack with `opacity(0)` for hidden tabs. Do NOT remove hidden tabs from the view tree — their GhosttySurfaceView (and PTY session) would be destroyed.
- **libghostty surface calls must happen on the main thread.** `ghostty_surface_read_text()`, `ghostty_surface_size()`, etc. are NOT thread-safe. Only move post-processing (regex, diffing) off main.
- **`saveImmediately()` must stay synchronous.** Called during `applicationWillTerminate` — async writes would be lost.
- **Tab is `@Observable` and `@MainActor`.** Property changes propagate to TabBarView, TerminalContainerView, MainView, StatusBarView. Guard redundant sets.
- **`ChatSessionEngine` is a pure state machine.** Do not add I/O, timers, or side effects to it. All side effects go through `ChatState.executeCommands()`.
- **`Package.swift` uses explicit `sources:` list.** New SwiftPM-covered files must be added manually. Test files auto-discover.
