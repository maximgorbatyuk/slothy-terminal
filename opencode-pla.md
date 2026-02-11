# Unified Chat Model and Mode Plan (OpenCode + Claude)

## Scope

Implement cross-provider chat controls so users can:

- See current `Model` and `Mode` for both OpenCode and Claude chats.
- Select `Model` and `Mode` before sending a message.
- Use a status bar directly below the chat textarea (composer status bar).

## Product Requirement (Confirmed Feasible)

This is implementable.

- OpenCode: metadata can be resolved authoritatively from `opencode export <sessionID>` (`providerID`, `modelID`, `mode`/`agent`).
- Claude: selected model/mode can be applied pre-send through transport args/profile mapping; resolved metadata can be inferred from stream/result events where available.

## Composer Status Bar (Below Textarea)

### UX behavior

- Location: immediately under `TextEditor` in `ChatInputView`.
- Controls:
  - Mode selector: `Build` / `Plan`
  - Model selector: provider/model
- Readouts:
  - `Selected`: what will be used for the next send
  - `Resolved`: what provider confirms for latest completed turn

### UI visualization

Default chat composer layout:

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ Chat                                                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  [assistant/user messages…]                                                  │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────────────────────────────┐ │
│ │ Type a message…                                                         │ │
│ │                                                                          │ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  Mode: [ Build ▾ ]   Model: [ anthropic/claude-sonnet-4-5 ▾ ]               │
│  Selected: Build · anthropic/claude-sonnet-4-5                               │
│  Resolved: Build · anthropic/claude-sonnet-4-5   ● Synced                    │
│                                                                              │
│                                                   [Stop] / [Send ↑]          │
└──────────────────────────────────────────────────────────────────────────────┘
```

OpenCode chat example while metadata reconciliation is in progress:

```text
Mode: [ Plan ▾ ]   Model: [ anthropic/claude-sonnet-4-5-20250929 ▾ ]
Selected: Plan · anthropic/claude-sonnet-4-5-20250929
Resolved: Build · anthropic/claude-sonnet-4-5-20250929   ○ Resolving…
```

Compact variant for small windows:

```text
[Mode: Build ▾] [Model: anthropic/claude-sonnet-4-5 ▾]    Resolved ✓
```

### New shared view/state

- `SlothyTerminal/Chat/Views/ChatComposerStatusBar.swift` (new)
- `SlothyTerminal/Chat/State/ChatState.swift` (update)
- `SlothyTerminal/Chat/Views/ChatInputView.swift` (embed status bar below editor)
- `SlothyTerminal/Chat/Views/ChatView.swift` (wire selected values to send flow)

## Shared Data Model

Introduce provider-neutral selection and resolved metadata:

- `ChatMode` enum: `build`, `plan`
- `ChatModelSelection` struct: `providerID`, `modelID`, `displayName`
- `ChatProviderResolvedMetadata` struct:
  - `resolvedProviderID`
  - `resolvedModelID`
  - `resolvedMode`
  - `source` (`selected`, `stream`, `export`)

## Phase 1: OpenCode Transport and Metadata

### 1) OpenCode stream models + parser

- `SlothyTerminal/Chat/OpenCode/OpenCodeStreamEvent.swift` (new)
- `SlothyTerminal/Chat/OpenCode/OpenCodeStreamEventParser.swift` (new)

Parse at least:

- `step_start`
- `text`
- `tool_use`
- `step_finish` (`tool-calls` vs `stop`)

### 2) OpenCode transport

- `SlothyTerminal/Chat/OpenCode/OpenCodeCLITransport.swift` (new)

Responsibilities:

- Spawn `opencode run --format json`
- Pass selected model (`--model`) and selected mode mapping (`--agent`)
- For continuity, pass `--session <savedID>` when present
- Drain stdout/stderr safely
- Emit typed events and termination callbacks

### 3) OpenCode metadata resolver

- `SlothyTerminal/Chat/OpenCode/OpenCodeSessionMetadataResolver.swift` (new)

Responsibilities:

- Run `opencode export <sessionID>` after `step_finish`
- Parse latest assistant `providerID`, `modelID`, `mode`/`agent`
- Return resolved metadata updates to `ChatState`

## Phase 2: Claude Parity for Model and Mode

### 4) Claude transport input controls

- `SlothyTerminal/Chat/Transport/ClaudeCLITransport.swift` (update)

Responsibilities:

- Accept selected model/mode from `ChatState`
- Pass model via Claude-supported args when available
- Implement mode mapping strategy:
  - Preferred: explicit CLI mode/profile args if available
  - Fallback: deterministic prompt profile policy per mode

### 5) Claude metadata resolution

- `SlothyTerminal/Chat/Transport/ClaudeCLITransport.swift` (update)
- `SlothyTerminal/Chat/State/ChatState.swift` (update)

Strategy:

- Default resolved metadata from selected values (instant, non-blocking)
- Upgrade with stream/result-derived metadata when present

## Phase 3: Engine and ChatState Wiring

### 6) Provider adapter integration

- `SlothyTerminal/Chat/State/ChatState.swift` (update)

Add provider-aware send flow:

- Send receives selected model/mode from composer status bar
- Transport initialized with selected values
- Continue storing session id per provider

### 7) Multi-segment turn safety (no regressions)

Ensure existing tool-use lifecycle remains correct:

- No turn finalization on intermediate stop/tool-call boundary
- Finalize only on terminal completion event

## Phase 4: Persistence

### 8) Persist selected and resolved metadata

- `SlothyTerminal/Chat/Storage/ChatSessionSnapshot.swift` (update)
- `SlothyTerminal/Chat/Models/ChatConversation.swift` (if metadata fields needed)

Persist:

- `selectedMode`
- `selectedModelProviderID`
- `selectedModelID`
- `resolvedMode`
- `resolvedModelProviderID`
- `resolvedModelID`

## Phase 5: UI and Product Wiring

### 9) Add composer status bar below textarea

- `SlothyTerminal/Chat/Views/ChatInputView.swift`
- `SlothyTerminal/Chat/Views/ChatView.swift`

### 10) Entry points

- Keep Claude Chat and OpenCode Chat both visible in:
  - start screen
  - new tab sheet
  - menu shortcuts

Likely files:

- `SlothyTerminal/Views/TerminalContainerView.swift`
- `SlothyTerminal/Views/MainView.swift`
- `SlothyTerminal/App/SlothyTerminalApp.swift`
- `SlothyTerminal/App/AppDelegate.swift`

## Phase 6: Testing

### 11) Parser and mapping tests

- `SlothyTerminalTests/OpenCodeStreamEventParserTests.swift` (new)
- Extend Claude parser/transport tests for model/mode passthrough

### 12) Composer selection tests

Validate for both providers:

- Selected mode/model shown before send
- Selected mode/model mapped into CLI args
- Resolved metadata updates after completion

### 13) Persistence/resume tests

- selected/resolved metadata survives app relaunch
- session resume preserves metadata context
- fallback behavior when metadata resolution fails

## Estimated Effort

- Shared composer status bar + state model: 1-2 days
- OpenCode transport/parser/resolver: 2-3 days
- Claude mode/model parity: 1-2 days
- Persistence + tests + polish: 2-3 days

Total: about 2 weeks for robust v1.

## Risks and Mitigations

- Provider schema drift: keep parsers tolerant and versioned.
- Mode parity mismatch across CLIs: document provider-specific mapping and surface effective mode clearly.
- Metadata lag (OpenCode export): show selected values immediately, then reconcile resolved values asynchronously.
