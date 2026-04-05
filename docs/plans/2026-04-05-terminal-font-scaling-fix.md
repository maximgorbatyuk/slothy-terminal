# Terminal Font Scaling Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent hidden terminal tabs from poisoning Ghostty's DPI/font state and guarantee that a tab becoming visible always re-sends a valid display-scale-plus-size snapshot.

**Architecture:** Keep the current tab architecture where inactive tabs stay alive, but stop treating hidden `0x0` views like normal Ghostty views. Centralize surface metric refresh so screen changes, backing changes, and tab activation all go through one zero-safe path that either applies a full refresh immediately or defers it until the view has a non-zero size.

**Tech Stack:** Swift, SwiftUI, AppKit, GhosttyKit C API, Swift Testing, Xcode build verification

---

### Task 1: Add a testable metric-policy helper

**Files:**
- Create: `SlothyTerminal/Services/GhosttySurfaceMetricPolicy.swift`
- Modify: `Package.swift:40-58`
- Test: `SlothyTerminalTests/GhosttySurfaceMetricPolicyTests.swift`

**Step 1: Write the failing test**

Create `SlothyTerminalTests/GhosttySurfaceMetricPolicyTests.swift` with focused policy tests:

```swift
import CoreGraphics
import Testing

@testable import SlothyTerminalLib

@Suite("GhosttySurfaceMetricPolicy")
struct GhosttySurfaceMetricPolicyTests {
  @Test("Stored content size wins when valid")
  func prefersStoredContentSize() {
    let result = GhosttySurfaceMetricPolicy.logicalSize(
      storedContentSize: CGSize(width: 700, height: 500),
      boundsSize: CGSize(width: 800, height: 600),
      frameSize: CGSize(width: 800, height: 600)
    )

    #expect(result == CGSize(width: 700, height: 500))
  }

  @Test("Falls back to bounds when stored content size is missing")
  func fallsBackToBounds() {
    let result = GhosttySurfaceMetricPolicy.logicalSize(
      storedContentSize: nil,
      boundsSize: CGSize(width: 800, height: 600),
      frameSize: CGSize(width: 0, height: 0)
    )

    #expect(result == CGSize(width: 800, height: 600))
  }

  @Test("Falls back to frame when bounds are zero")
  func fallsBackToFrame() {
    let result = GhosttySurfaceMetricPolicy.logicalSize(
      storedContentSize: nil,
      boundsSize: CGSize(width: 0, height: 0),
      frameSize: CGSize(width: 800, height: 600)
    )

    #expect(result == CGSize(width: 800, height: 600))
  }

  @Test("Returns nil when every candidate size is zero")
  func rejectsZeroSizedView() {
    let result = GhosttySurfaceMetricPolicy.logicalSize(
      storedContentSize: nil,
      boundsSize: .zero,
      frameSize: .zero
    )

    #expect(result == nil)
  }

  @Test("Scale refresh is blocked for zero-sized frames")
  func blocksScaleRefreshForZeroFrame() {
    #expect(GhosttySurfaceMetricPolicy.canComputeScale(frameSize: .zero) == false)
    #expect(GhosttySurfaceMetricPolicy.canComputeScale(frameSize: CGSize(width: 1, height: 1)))
  }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter GhosttySurfaceMetricPolicyTests`

Expected: FAIL because `GhosttySurfaceMetricPolicy` does not exist yet.

**Step 3: Write minimal implementation**

Create `SlothyTerminal/Services/GhosttySurfaceMetricPolicy.swift`:

```swift
import CoreGraphics

enum GhosttySurfaceMetricPolicy {
  static func logicalSize(
    storedContentSize: CGSize?,
    boundsSize: CGSize,
    frameSize: CGSize
  ) -> CGSize? {
    let candidates = [storedContentSize, boundsSize, frameSize]

    for candidate in candidates.compactMap({ $0 }) {
      guard candidate.width > 0,
            candidate.height > 0
      else {
        continue
      }

      return candidate
    }

    return nil
  }

  static func canComputeScale(frameSize: CGSize) -> Bool {
    frameSize.width > 0 && frameSize.height > 0
  }
}
```

Add the new source to `Package.swift` immediately after `Services/GhosttySurfaceMetricsCache.swift` while it still exists.

**Step 4: Run test to verify it passes**

Run: `swift test --filter GhosttySurfaceMetricPolicyTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add Package.swift SlothyTerminal/Services/GhosttySurfaceMetricPolicy.swift SlothyTerminalTests/GhosttySurfaceMetricPolicyTests.swift
git commit -m "test: add terminal metric policy coverage"
```

### Task 2: Make `GhosttySurfaceView` zero-safe and remove wrapper-side size dedup

**Files:**
- Modify: `SlothyTerminal/Terminal/GhosttySurfaceView.swift:23-35`
- Modify: `SlothyTerminal/Terminal/GhosttySurfaceView.swift:218-227`
- Modify: `SlothyTerminal/Terminal/GhosttySurfaceView.swift:295-357`
- Modify: `SlothyTerminal/Terminal/GhosttySurfaceView.swift:434-439`
- Modify: `Package.swift:48`
- Delete: `SlothyTerminal/Services/GhosttySurfaceMetricsCache.swift`
- Delete: `SlothyTerminalTests/GhosttySurfaceMetricsCacheTests.swift`

**Step 1: Write the failing test**

This task is app-only, so the failing regression is behavioral rather than a direct SwiftPM unit test.

Reproduce manually before changing code:

1. Open two terminal tabs on the built app.
2. Put the window on a Retina display.
3. Switch to tab A, then tab B, then tab A again.
4. Observe that one tab can show the wrong physical font size.

Expected before fix: reproduction still occurs intermittently.

**Step 2: Remove the wrapper dedup and introduce pending refresh state**

In `GhosttySurfaceView.swift`:

1. Remove `surfaceMetricsCache`.
2. Replace `private var contentSize: NSSize = .zero` with upstream-style storage:

```swift
private var contentSizeBacking: NSSize?
private var contentSize: NSSize {
  get { contentSizeBacking ?? frame.size }
  set { contentSizeBacking = newValue }
}
```

3. Add:

```swift
private var pendingSurfaceMetricsRefresh = false
```

4. Delete `invalidateSurfaceMetrics()`.
5. Remove `surfaceMetricsCache.reset()` from `destroySurface()`.
6. Remove `GhosttySurfaceMetricsCache.swift` from `Package.swift` and delete its old tests.

**Step 3: Centralize the full metric refresh path**

In `GhosttySurfaceView.swift`, add a helper that applies both content scale and size only when the view has a valid size:

```swift
private func refreshSurfaceMetricsIfPossible() {
  updateDisplayId()

  if let window {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.contentsScale = window.backingScaleFactor
    CATransaction.commit()
  }

  guard let surface else {
    return
  }

  guard GhosttySurfaceMetricPolicy.canComputeScale(frameSize: frame.size),
        let logicalSize = GhosttySurfaceMetricPolicy.logicalSize(
          storedContentSize: contentSizeBacking,
          boundsSize: bounds.size,
          frameSize: frame.size
        )
  else {
    pendingSurfaceMetricsRefresh = true
    return
  }

  let backingRect = convertToBacking(NSRect(origin: .zero, size: logicalSize))
  let xScale = backingRect.size.width / logicalSize.width
  let yScale = backingRect.size.height / logicalSize.height

  ghostty_surface_set_content_scale(surface, xScale, yScale)
  ghostty_surface_set_size(surface, UInt32(backingRect.size.width), UInt32(backingRect.size.height))
  pendingSurfaceMetricsRefresh = false
}
```

**Step 4: Route the existing triggers through the new helper**

Update the existing methods:

1. `viewDidChangeBackingProperties()` should call only `refreshSurfaceMetricsIfPossible()`.
2. `handleScreenChange()` should remain async, but the async block should call `refreshSurfaceMetricsIfPossible()` instead of `viewDidChangeBackingProperties()` directly.
3. `layout()` should keep `sizeDidChange(bounds.size)`, then run:

```swift
if pendingSurfaceMetricsRefresh {
  refreshSurfaceMetricsIfPossible()
}
```

4. `sizeDidChange(_:)` should keep storing `contentSize = size`, skip zero sizes, and call `ghostty_surface_set_size` directly without any wrapper cache guard.
5. `setSurfaceSize(width:height:)` should only guard `surface != nil` and `width > 0 && height > 0` before calling `ghostty_surface_set_size`.

**Step 5: Run verification**

Run:

```bash
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO
swift test
```

Expected:

1. Xcode build passes.
2. `swift test` passes after removing the obsolete cache tests and adding the new policy tests.

**Step 6: Commit**

```bash
git add Package.swift SlothyTerminal/Terminal/GhosttySurfaceView.swift SlothyTerminal/Services/GhosttySurfaceMetricPolicy.swift SlothyTerminalTests/GhosttySurfaceMetricPolicyTests.swift SlothyTerminalTests/GhosttySurfaceMetricsCacheTests.swift
git commit -m "fix: make ghostty surface metric refresh zero-safe"
```

### Task 3: Repair tab activation so a revealed tab always re-sends both scale and size

**Files:**
- Modify: `SlothyTerminal/Views/TerminalView.swift:94-105`

**Step 1: Write the failing test**

This path is also app-only. Reproduce manually before the change:

1. Launch the app.
2. Open two terminal tabs on the same display.
3. Alternate between them several times.

Expected before fix: one tab can retain stale font size after being hidden.

**Step 2: Replace cache invalidation with an explicit refresh request**

When `isActive` becomes `true`, replace:

```swift
nsView.invalidateSurfaceMetrics()
nsView.needsLayout = true
```

with a single app-level request method, for example:

```swift
nsView.requestSurfaceMetricsRefresh()
```

Add this method to `GhosttySurfaceView.swift`:

```swift
func requestSurfaceMetricsRefresh() {
  pendingSurfaceMetricsRefresh = true
  needsLayout = true

  DispatchQueue.main.async { [weak self] in
    guard let self else {
      return
    }

    self.layoutSubtreeIfNeeded()
    self.refreshSurfaceMetricsIfPossible()
  }
}
```

This ensures activation does not rely on a size-only layout path. It requests a full refresh and retries after SwiftUI has had one runloop to restore a non-zero frame.

**Step 3: Run verification**

Run the same verification commands:

```bash
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO
swift test
```

Expected: PASS.

**Step 4: Commit**

```bash
git add SlothyTerminal/Views/TerminalView.swift SlothyTerminal/Terminal/GhosttySurfaceView.swift
git commit -m "fix: refresh ghostty metrics when tab becomes active"
```

### Task 4: Manual regression sweep against the real bug matrix

**Files:**
- No source changes expected

**Step 1: Same-monitor tab switching**

1. Open at least two terminal tabs.
2. Switch back and forth rapidly.
3. Confirm font size remains physically identical between tabs.

**Step 2: Display transition with hidden tabs present**

1. Open at least two terminal tabs.
2. Leave one tab hidden.
3. Move the window between displays with different DPI, or connect/disconnect the external display.
4. Activate the previously hidden tab.
5. Confirm it renders at the correct size immediately.

**Step 3: Normal resize path**

1. Resize the window repeatedly.
2. Confirm rows/columns update correctly.
3. Confirm there is no prompt corruption beyond the known shell behavior from legitimate resize signals.

**Step 4: Final verification commands**

Run:

```bash
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO
swift test
git status --short
```

Expected:

1. Build passes.
2. Tests pass.
3. Only intended files are modified.

**Step 5: Commit**

```bash
git add -A
git commit -m "test: verify terminal font scaling regressions"
```

## Notes

- Do not change `SlothyTerminal/Views/TerminalContainerView.swift` in the first pass. The current `0x0` hidden-tab strategy can remain as long as `GhosttySurfaceView` stops applying scale updates while hidden and guarantees a full refresh when visible again.
- Do not change `handleScreenChange()` semantics beyond routing it through the zero-safe helper.
- Do not change font configuration, app config, or Ghostty app initialization.
- Removing the wrapper-side size dedup is low risk because Ghostty already deduplicates unchanged sizes internally in `ghostty/src/apprt/embedded.zig`.
- The most important behavioral invariant after this fix is: a zero-sized hidden surface must never send `ghostty_surface_set_content_scale`.

## Expected Outcome

This plan should fix both observed symptoms:

1. Display changes will no longer poison hidden surfaces with invalid scale.
2. Tab activation will no longer rely on a size-only recovery path.
3. A hidden tab that becomes visible will always receive one valid full metric refresh after layout settles.
