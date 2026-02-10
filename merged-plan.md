# Merged Plan: Production Chat + Primary UX

## Outcome

- Chat becomes the default Claude experience (like Claude/Codex app).
- Under the hood, it is built on a robust session engine (not a fragile UI wrapper).
- You get both: reliability first, premium rendering/polish second.

## Guiding Principles

- P0 Reliability before P1 polish for anything that risks regressions.
- Layered architecture: engine -> transport -> storage -> UI adapter.
- Incremental visible wins each milestone (so product progress is obvious).
- Test gates before removing Beta.

## Track A (P0): Core Engine and Reliability

### A1. Session Engine and State Machine

- Introduce `ChatSessionEngine`, `ChatSessionState`, `ChatSessionEvent`.
- Move orchestration out of `ChatState` into engine.
- Enforce explicit states: idle/starting/ready/sending/streaming/cancelling/recovering/failed/terminated.
- Add transition table plus invariant checks (single in-flight turn, deterministic end states).

### A2. Claude Transport Abstraction

- Add `ClaudeChatTransport` protocol plus `ClaudeCLITransport`.
- Isolate process spawn/write/read/interrupt/exit handling from UI.
- Emit typed transport events and typed termination reasons.
- Add Claude CLI capability checks at startup (resume flags, streaming behavior).

### A3. Persistence and Resume Foundation

- Add `ChatSessionStore` plus `ChatSessionSnapshot`.
- Persist sessions in `~/Library/Application Support/SlothyTerminal/chats/` with atomic writes plus debounce.
- Restore snapshot on app relaunch.
- Resume transport/session linkage when possible.

### A4. Resilience Semantics

- True cancel (transport-level interrupt), not just UI stop.
- Add `retryLastTurn()` and recover-after-crash flow.
- Connection state model (`connected/reconnecting/disconnected/failed`) surfaced to UI.

### A5. Observability and Tests

- Add logger category `.chat`.
- Structured logs for state transitions, parse errors, store errors, recovery attempts.
- Tests:
  - engine transition tests
  - parser malformed/variant tests
  - store roundtrip/corruption/migration tests
  - integration tests with mock transport
  - relaunch/resume smoke test

## Track B (P1): Product UX and Chat-First Experience

### B1. Promote Chat to Primary Entry

- Make Chat first in menu and empty state.
- Shortcut strategy:
  - `Cmd+T` => New Chat
  - `Cmd+Shift+T` => New Claude TUI tab
- Remove Beta wording only after P0 test gate passes.
- Add configurable default tab mode in settings (`defaultTabMode`).

### B2. Rich Markdown Rendering

- Add `swift-markdown` AST rendering for completed messages.
- Streaming optimization: lightweight inline rendering while tokens stream, full block render at completion.
- Build dedicated views for headings/lists/blockquote/tables/code fences.

### B3. Tool Use Rendering

- Add `ToolBlockRouter`.
- Specialized tool views:
  - bash output style
  - file read/write/edit style
  - search results style
  - generic fallback
- Pair `tool_use` plus `tool_result` by tool ID for coherent visualization.

### B4. Interaction Polish

- Reusable copy button component.
- Better status bar: connection state plus token totals plus clear conversation.
- Better streaming indicator (thinking/tool-running context).
- Input improvements: history navigation plus improved sizing.
- Empty state suggestions/chips.

## Recommended Execution Order (Best Combined)

1. Week 1
- A1 (state machine) plus A2 (transport abstraction skeleton)
- B1 (chat-first menu/entry wiring) can start in parallel (without removing Beta yet)

2. Week 2
- A3 (persistence/resume) plus A5 tests (engine/parser first)
- B2 markdown renderer starts in parallel

3. Week 3
- A4 resilience semantics (cancel/retry/recover)
- B3 tool rendering

4. Week 4
- B4 polish plus A5 integration/relaunch tests
- Remove Beta labels only if acceptance gates are green

## Acceptance Gates (Must Pass Before Production Chat)

- Process crash does not lose conversation continuity.
- App relaunch restores session and can continue conversation.
- Cancel truly interrupts generation.
- Retry and recover behavior is deterministic and tested.
- No regressions in non-chat tabs.
- Markdown and tool rendering work for streaming plus completed responses.

## File-Level Target Map (High-level)

- Engine/state: `SlothyTerminal/Chat/Engine/*` (new)
- Transport: `SlothyTerminal/Chat/Transport/*` (new)
- Store: `SlothyTerminal/Chat/Storage/*` (new)
- Adapter updates: `SlothyTerminal/Chat/State/ChatState.swift`
- UI updates: `SlothyTerminal/Chat/Views/*`, `SlothyTerminal/Views/TerminalContainerView.swift`, `SlothyTerminal/App/SlothyTerminalApp.swift`, `SlothyTerminal/Views/SettingsView.swift`
- Logging: `SlothyTerminal/Services/Logger.swift`
- Tests: `SlothyTerminalTests/Chat*Tests.swift` (new)

## Key Tradeoff Decision (Recommended Default)

- Persist snapshots as plain JSON first (fast to ship, easy debug), then optionally add encrypted-at-rest as a follow-up.
