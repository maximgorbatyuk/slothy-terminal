---
name: swift-perf-audit
description: Full-stack Swift/SwiftUI performance and UX audit for SlothyTerminal. Chains all Swift-related skills, systematically scans the codebase for main-thread blocking, view invalidation storms, animation overhead, and async anti-patterns, then applies targeted fixes. Use when the UI feels sluggish, frozen, or janky during terminal/chat activity.
---

# SlothyTerminal Swift Performance & UX Audit

## Overview

Comprehensive performance audit for SlothyTerminal's macOS SwiftUI + libghostty terminal app. This skill orchestrates multiple Swift-related skills into a single systematic workflow that identifies and fixes UI freezes, excessive re-renders, main-thread blocking, and animation jank.

## Prerequisites

Before starting, invoke these skills to load their guidelines:

1. `/developing-with-swift` — Swift style rules (required by CLAUDE.md)
2. `/swiftui-performance-audit` — SwiftUI performance diagnosis framework
3. `/swiftui-expert-skill` — SwiftUI best practices and review checklist
4. `/swiftui-ui-patterns` — Component-level patterns and examples
5. `/swift-testing-expert` — For writing regression tests after fixes

**Show the user which skills you loaded before proceeding.**

## Workflow

### Phase 1: Collect Symptoms

Ask the user (or infer from context):
- Which interaction feels slow? (tab switching, terminal output, chat streaming, startup, split view)
- How many tabs are typically open?
- Is the freeze continuous or triggered by specific actions?
- Is Telegram relay active during the freeze?

### Phase 2: Codebase Scan

Launch **3 parallel exploration agents** targeting the areas below. Each agent should read full file contents and flag issues.

#### Agent A: View Layer & State Propagation
Scan for:
- `@Observable` classes with broad state that triggers view invalidation storms
- Computed properties in `body` that do filtering, sorting, or allocation
- `onChange` modifiers that cascade or fire too frequently
- `withAnimation` in hot paths (streaming, polling, per-character updates)
- `ForEach` iterating more items than needed (all tabs vs visible tabs)
- `.repeatForever` animations on views that may be hidden
- `Timer.publish` instances on the main run loop
- `GeometryReader` in frequently re-rendered subtrees

Key files:
```
SlothyTerminal/Views/MainView.swift
SlothyTerminal/Views/TabBarView.swift
SlothyTerminal/Views/TerminalContainerView.swift
SlothyTerminal/Views/SidebarView.swift
SlothyTerminal/Chat/Views/ChatMessageListView.swift
SlothyTerminal/Chat/Views/MessageBubbleView.swift
SlothyTerminal/App/AppState.swift
```

#### Agent B: Terminal & Native Layer
Scan for:
- Synchronous libghostty C calls on the main thread (`ghostty_surface_read_text`, `ghostty_surface_read_selection`)
- `ANSIStripper.strip()` (regex) on the main thread
- Callbacks from C that dispatch heavy work to `DispatchQueue.main`
- `readViewportText()` called from hot paths (render callbacks, tab switches, polling)
- `DispatchQueue.main.asyncAfter` that queues up during rapid output

Key files:
```
SlothyTerminal/Terminal/GhosttySurfaceView.swift
SlothyTerminal/Terminal/GhosttyApp.swift
SlothyTerminal/Services/StatsParser.swift
SlothyTerminal/Services/ActivityDetectionGate.swift
SlothyTerminal/Telegram/Relay/TerminalOutputPoller.swift
```

#### Agent C: Services & Async Layer
Scan for:
- `Process` + `waitUntilExit()` without timeout (blocks thread indefinitely)
- Synchronous file I/O on the main thread (`Data.write`, `Data(contentsOf:)`)
- `DispatchSemaphore.wait` on the main thread
- Frequent `@Observable` property mutations that trigger global re-renders
- Config saves that cascade through `didSet`
- `Task.detached` that captures `self` without timeout protection

Key files:
```
SlothyTerminal/Chat/State/ChatState.swift
SlothyTerminal/Chat/Storage/ChatSessionStore.swift
SlothyTerminal/Services/ConfigManager.swift
SlothyTerminal/Services/GitService.swift
SlothyTerminal/Services/GitProcessRunner.swift
SlothyTerminal/Services/OpenCodeCLIService.swift
SlothyTerminal/Models/Tab.swift
SlothyTerminal/Models/Workspace.swift
```

### Phase 3: Classify & Prioritize

Group findings into severity tiers:

| Tier | Category | Symptoms |
|------|----------|----------|
| **CRITICAL** | Main thread blocking | Hard freeze (>500ms), unresponsive UI |
| **HIGH** | View invalidation storms | Janky scrolling, sluggish tab switching |
| **HIGH** | Animation pile-up | Stuttering during streaming, high CPU at idle |
| **MEDIUM** | Redundant computation | Slow window title, delayed status bar updates |
| **LOW** | One-time costs | Startup delay, first-tab creation lag |

For each finding, provide:
- **File:line** reference
- **Root cause** (one sentence)
- **Impact** (what the user sees)
- **Fix** (specific code change)
- **Effort** (Low / Medium / High)

### Phase 4: Apply Fixes

Apply fixes in priority order. For each fix:

1. Read the target file
2. Make the minimal change
3. Do NOT refactor surrounding code
4. Do NOT add comments, docstrings, or type annotations to unchanged code

#### Common Fix Patterns for This Project

**Main-thread blocking (libghostty reads):**
```swift
// BEFORE: Sync regex on main thread
let snapshot = ANSIStripper.strip(text)

// AFTER: Dispatch regex to background, return result to main
DispatchQueue.global(qos: .utility).async { [weak self] in
  let snapshot = ANSIStripper.strip(text)
  DispatchQueue.main.async {
    self?.lastViewportSnapshot = snapshot
  }
}
```

**Process timeout protection:**
```swift
// BEFORE: Blocks indefinitely
process.waitUntilExit()

// AFTER: 5s timeout with termination
let done = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
  process.waitUntilExit()
  done.signal()
}
if done.wait(timeout: .now() + 5) == .timedOut {
  process.terminate()
  return nil
}
```

**Redundant @Observable state writes:**
```swift
// BEFORE: Always sets, even if already true
func markTerminalBusy() {
  isTerminalBusy = true
}

// AFTER: Guard prevents unnecessary observation notifications
func markTerminalBusy() {
  guard !isTerminalBusy else { return }
  isTerminalBusy = true
}
```

**Throttled auto-scroll during streaming:**
```swift
// BEFORE: Animated scroll on every character
.onChange(of: lastMessageText) {
  withAnimation(.easeOut(duration: 0.1)) {
    proxy.scrollTo("bottom", anchor: .bottom)
  }
}

// AFTER: Throttled, non-animated scroll
@State private var lastAutoScrollDate = Date.distantPast

.onChange(of: lastMessageText) {
  let now = Date()
  guard now.timeIntervalSince(lastAutoScrollDate) > 0.1 else { return }
  lastAutoScrollDate = now
  proxy.scrollTo("bottom", anchor: .bottom)
}
```

**Background disk writes:**
```swift
// BEFORE: Timer fires sync write on main thread
private func flushPendingSnapshot() {
  writeSnapshot(snapshot)  // blocks main
}

// AFTER: Serial background queue
private let writeQueue = DispatchQueue(label: "...", qos: .utility)

private func flushPendingSnapshot() {
  writeQueue.async { [self] in
    writeSnapshot(snapshot)
  }
}
// Keep saveImmediately() synchronous for app termination
```

**Removing redundant onChange triggers:**
```swift
// BEFORE: Observes computed property that refilters on every tab change
.onChange(of: appState.visibleTabs.count) { updateWindowTitle() }

// AFTER: Observe the actual trigger
.onChange(of: appState.activeWorkspaceID) { updateWindowTitle() }
```

### Phase 5: Verify

After all fixes:

1. Run `swift build` — must succeed with no new warnings
2. Run `swift test` — all tests must pass
3. Run `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO` — must succeed
4. Report results to the user

If a test fails, investigate and fix before reporting completion.

### Phase 6: Report

Present a summary table:

```
| # | Fix | File | Severity | Status |
|---|-----|------|----------|--------|
| 1 | ... | ...  | CRITICAL | Done   |
```

## Architecture Constraints (SlothyTerminal-Specific)

These constraints MUST be respected during fixes:

- **PTY lifecycle is tied to SwiftUI view hierarchy.** Terminal tabs use a ZStack with `opacity(0)` for hidden tabs. Do NOT remove hidden tabs from the view tree — their GhosttySurfaceView (and PTY session) would be destroyed.
- **libghostty surface calls must happen on the main thread.** `ghostty_surface_read_text()`, `ghostty_surface_size()`, etc. are NOT thread-safe. Only move post-processing (regex, diffing) off main.
- **`saveImmediately()` must stay synchronous.** Called during `applicationWillTerminate` — async writes would be lost.
- **Tab is `@Observable` and `@MainActor`.** Property changes propagate to TabBarView, TerminalContainerView, MainView, StatusBarView. Guard redundant sets.
- **`ChatSessionEngine` is a pure state machine.** Do not add I/O, timers, or side effects to it. All side effects go through `ChatState.executeCommands()`.
- **`Package.swift` uses explicit `sources:` list.** New SwiftPM-covered files must be added manually. Test files auto-discover.

## Anti-Patterns to Always Flag

1. `process.waitUntilExit()` without timeout — blocks thread indefinitely
2. `Data.write(to:options:.atomic)` on main thread — blocks during fsync
3. `withAnimation` in `onChange(of: streamingText)` — animations queue up per character
4. `@Observable` property set to same value — triggers observation even when unchanged
5. `ForEach(appState.tabs)` when `visibleTabs` would suffice — iterates all workspaces
6. `Timer.publish(every:on:.main)` on hidden views — consumes frame budget
7. `.repeatForever` animation on view that may be invisible — renders continuously
8. `ANSIStripper.strip()` on main thread — regex engine can stall on large input
9. Nested `DispatchQueue.main.asyncAfter` in render callbacks — queues pile up during burst output
10. Computed `visibleTabs` accessed N times per render — O(n) filter repeated unnecessarily

## When NOT to Use This Skill

- For adding new features (use `/developing-with-swift` + `/swiftui-expert-skill`)
- For writing tests (use `/swift-testing-expert`)
- For code style review without performance focus (use `/code-reviewer`)
- For chat engine logic changes (the engine is a pure state machine — no UI involvement)
