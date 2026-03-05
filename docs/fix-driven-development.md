# Fix-Driven Development

## Bug: Paste in second tab goes to first tab

### Root cause

The app keeps all terminal views alive in a `ZStack` to preserve sessions when switching tabs. Only the active one is visible and hit-testable, but inactive `GhosttySurfaceView` instances still exist.

Paste (`Cmd+V`) was handled in `GhosttySurfaceView.performKeyEquivalent(with:)` without requiring that view to be the current first responder. During some tab switches, first responder was not reliably moved to the active terminal yet, so the first mounted terminal view could still consume the key equivalent and trigger Ghostty's `paste_from_clipboard` binding.

That made paste text appear in tab 1 even when tab 2 looked active.

### Applied fix

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

### Verification

- Manual: reproducer no longer occurs; paste now lands in the currently active tab.
- Automated: `swift test` passed (`348 tests`, `0 failures`).
