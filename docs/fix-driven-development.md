# Fix-Driven Development

## Known Issues & Pitfalls

- `BuildConfig` uses `fatalError()` on missing config files — should degrade gracefully
- GhosttyApp C callback trampolines (free functions) cannot be `@MainActor`; helper methods they call must be `nonisolated`
- To open the native Settings window programmatically, use `SettingsLink` (SwiftUI view), not `NSApp.sendAction(Selector(("showSettingsWindow:")))` — the latter logs an error on macOS 14+
- `ModalRouter` in `MainView.swift` maps `ModalType` cases to views — keep it in sync when adding new modal types
- `AppState.pendingSettingsSection` allows pre-selecting a `SettingsSection` tab when the native Settings window opens
- All git `Process` calls must go through `GitProcessRunner.run()` — it reads pipe data before `waitUntilExit()` to prevent deadlocks when output exceeds the 64KB pipe buffer
- **Terminal focus in `updateNSView`** — `ghostty_surface_set_focus` must only be called on actual `isTabActive` transitions (not every SwiftUI view update). Redundant focus calls cause libghostty to re-evaluate the viewport scroll position, producing a visible scroll-to-top-then-bottom artifact when switching tabs.
- **Drag-drop reordering in vertical lists** requires two mitigations that horizontal tab bars don't need:
  1. **Use `swapAt` instead of `move(before:)`** — "insert before target" is a no-op when dragging downward (source is already before target). Swap works in both directions.
  2. **Add a cooldown after each swap** — after `swapWorkspaces` triggers a `ForEach` re-render, the swapped view can animate through the cursor and fire `dropEntered` again, immediately undoing the swap. A ~300ms cooldown flag prevents this double-swap.
  3. **Avoid `NSItemProvider`-wrapping classes with `deinit` cleanup** — `deinit` dispatches `Task { @MainActor }` which races with the next drag's `onDrag` closure, clearing `draggedID` after it was just set. Use plain `NSString` for the provider instead.

## Bugs

### Paste in second tab goes to first tab

#### Root cause

The app keeps all terminal views alive in a `ZStack` to preserve sessions when switching tabs. Only the active one is visible and hit-testable, but inactive `GhosttySurfaceView` instances still exist.

Paste (`Cmd+V`) was handled in `GhosttySurfaceView.performKeyEquivalent(with:)` without requiring that view to be the current first responder. During some tab switches, first responder was not reliably moved to the active terminal yet, so the first mounted terminal view could still consume the key equivalent and trigger Ghostty's `paste_from_clipboard` binding.

That made paste text appear in tab 1 even when tab 2 looked active.

#### Applied fix

1. **Responder gate for key equivalents**
   - File: `SlothyTerminal/Terminal/GhosttySurfaceView.swift`
   - Change: early return to `super` unless `window?.firstResponder === self`.
   - Effect: only the focused terminal view can handle copy/paste key equivalents.

2. **Claim focus on mouse down**
   - File: `SlothyTerminal/Terminal/GhosttySurfaceView.swift`
   - Change: in `mouseDown`, `rightMouseDown`, and `otherMouseDown`, call `window?.makeFirstResponder(self)` when needed.
   - Effect: clicking a terminal reliably makes that tab's surface the responder before keyboard shortcuts.

3. **Safer active-tab responder update**
   - File: `SlothyTerminal/Views/TerminalView.swift`
   - Change: in `updateNSView`, when `isActive == true`, re-apply `makeFirstResponder` asynchronously if still missing.
   - Effect: avoids timing issues during SwiftUI updates where responder assignment can be momentarily stale.

#### Verification

- Manual: reproducer no longer occurs; paste now lands in the currently active tab.
- Automated: `swift test` passed (`348 tests`, `0 failures`).
