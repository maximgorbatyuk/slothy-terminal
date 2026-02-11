# Codex-Style Chat Implementation Plan (Option 2)

## Goal

Transform SlothyTerminal chat mode into a production-grade, Claude/Codex-style chat engine with:

- reliable multi-turn continuity
- recovery after process/app restart
- persistent conversation history
- robust state handling for streaming/cancel/retry/error
- full observability and test coverage

## Current Baseline

- Chat UI exists and streams via Claude CLI NDJSON.
- `ChatState` currently combines UI state, process lifecycle, parsing, and orchestration.
- `sessionId` is captured but not used for recovery/resume.
- Conversation history exists in memory but is not persisted.
- Cancel flow is mostly UI-level, not transport-strong.

## Architecture Direction

Split current monolithic chat logic into layers:

1. **Engine layer** (state machine and business rules)
2. **Transport layer** (Claude process IO and protocol handling)
3. **Storage layer** (persistent chat snapshots and restore)
4. **UI adapter layer** (`ChatState` as observable facade)

---

## Phase 1 — Session State Machine Core

### Objectives

- Introduce explicit lifecycle states:
  - `idle`
  - `starting`
  - `ready`
  - `sending`
  - `streaming`
  - `cancelling`
  - `recovering`
  - `failed`
  - `terminated`
- Define strict transition rules and guardrails.
- Ensure one in-flight turn at a time and deterministic transitions.

### Deliverables

- `ChatSessionEngine`
- `ChatSessionState`
- `ChatSessionEvent`
- Transition table documentation

### Notes

- `ChatState` should delegate all orchestration decisions to the engine.
- Invalid transitions should be logged and safely ignored/fail-fast based on severity.

---

## Phase 2 — Claude Transport Abstraction

### Objectives

- Isolate process management in `ClaudeCLITransport`.
- Keep spawn, stdin writes, stdout parsing, termination, interruption out of UI/model code.
- Support recovery lifecycle for unexpected process exits.

### Deliverables

- `ClaudeChatTransport` protocol
- `ClaudeCLITransport` implementation
- Typed transport events mapped into engine events
- Capability checks for installed Claude CLI behavior

### Notes

- Parser errors become typed recoverable errors (not silent drops).
- Transport should emit explicit termination reason (EOF, signal, error, non-zero exit).

---

## Phase 3 — Persistent Conversation Store

### Objectives

- Persist every chat session to disk with:
  - message timeline
  - token usage
  - session metadata
  - working directory linkage
  - Claude session linkage metadata
- Restore sessions on app restart.

### Deliverables

- `ChatSessionStore`
- `ChatSessionSnapshot` codable model(s)
- Autosave (debounced + atomic writes)
- Startup hydration flow in app state/tab restoration

### Storage Plan

- Path: `~/Library/Application Support/SlothyTerminal/chats/`
- One file per session + optional index file for fast lookup by project directory.

---

## Phase 4 — Cancel / Retry / Resume Semantics

### Objectives

- Implement transport-level cancel (actual interruption).
- Add retry-last-turn behavior with proper state transitions.
- Add continue-after-error and recover-after-crash flows.

### Deliverables

- Engine APIs:
  - `send(message:)`
  - `cancelCurrentTurn()`
  - `retryLastTurn()`
  - `recoverSession()`
- UI actions wired to real engine transitions.

### Notes

- Cancel should always leave session in a valid, resumable state.
- Retry should not duplicate token accounting.

---

## Phase 5 — UI and Timeline Refinement

### Objectives

- Drive chat UI from structured timeline events.
- Show explicit session status in header:
  - Connected
  - Streaming
  - Recovering
  - Interrupted
  - Error
- Improve sidebar stats to read from persistent session data.

### Deliverables

- Updated `ChatView` status handling
- Timeline-driven message list updates
- Sidebar session metadata and token totals sourced from store/engine

---

## Phase 6 — Observability and Diagnostics

### Objectives

- Add chat-specific structured logging.
- Track key lifecycle breadcrumbs:
  - state transitions
  - transport starts/stops
  - parse failures
  - persistence failures
  - recovery attempts/outcomes

### Deliverables

- Logger category: `.chat`
- Standardized log fields (session ID, turn ID, state, error type)

---

## Phase 7 — Test Coverage

### Objectives

Build confidence before removing beta label.

### Required Tests

1. **Engine tests**
   - valid transitions
   - invalid transition rejection
   - cancel/stream race behavior
2. **Parser tests**
   - all expected event variants
   - malformed NDJSON handling
3. **Store tests**
   - save/load roundtrip
   - corruption fallback
   - migration compatibility
4. **Integration tests (mock transport)**
   - send -> stream -> result
   - cancel in-flight
   - recovery after forced transport failure
5. **App-level smoke test**
   - relaunch and continue existing chat session

---

## Suggested Implementation Sequence

1. Introduce engine types and tests first.
2. Extract transport from `ChatState`.
3. Wire parser into typed events.
4. Add persistence store and hydration path.
5. Implement cancel/retry/recover semantics.
6. Upgrade UI status and timeline binding.
7. Add logging + polish.
8. Run full tests and regression checks.

---

## Definition of Done

- Chat continuity survives process restarts and app relaunch.
- Cancel truly interrupts generation.
- Retry and resume are stable and predictable.
- Persistent transcript and usage stats reload correctly.
- No regressions for terminal tabs and existing agent flows.
- Beta labels can be removed once test gates are green.

---

## Effort Estimate

- **4–7 focused dev days**, depending on Claude CLI edge-case handling and recovery test complexity.

---

## Product Decision (Recommended)

Default to plain JSON persistence in app support (fast + debuggable), and optionally add encrypted-at-rest as a follow-up enhancement if needed.
