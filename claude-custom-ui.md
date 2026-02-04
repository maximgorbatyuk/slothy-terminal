# Claude Custom UI Investigation

This document contains investigation results and implementation plan for building a custom chat-like UI for Claude interactions instead of (or alongside) the terminal emulator.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Authentication Options](#authentication-options)
3. [Architecture Options](#architecture-options)
4. [Recommended Approach: Hybrid Terminal + Overlay](#recommended-approach-hybrid-terminal--overlay)
5. [Implementation Plan](#implementation-plan)
6. [Technical Details](#technical-details)
7. [Risks and Mitigations](#risks-and-mitigations)

---

## Executive Summary

### Goal
Replace or augment the terminal-based UI with a modern chat interface similar to Claude Desktop or Cursor, featuring:
- Message bubbles for user/assistant
- Syntax-highlighted code blocks
- Visual tool call representations (file edits, bash commands)
- Streaming text display

### Key Finding
Claude CLI supports `--output-format stream-json` which outputs **structured JSON events** instead of ANSI-formatted terminal text. This enables clean parsing without reverse-engineering terminal output.

### Recommendation
**Hybrid Approach** - Keep terminal as backend, add message UI overlay that parses `stream-json` output. This provides:
- Incremental migration path
- Terminal fallback for edge cases
- Compatibility with Claude CLI updates
- ~2-3 weeks implementation time

---

## Authentication Options

### Option 1: API Key (Recommended for Custom Apps)

| Aspect | Details |
|--------|---------|
| **How it works** | User enters API key from console.anthropic.com |
| **Billing** | Pay-per-token (~$3-15/M input, ~$15-75/M output) |
| **Registration** | None required - use public API |
| **Feasibility** | ✅ Works today |

### Option 2: OAuth (Pro/Max Subscription)

| Aspect | Details |
|--------|---------|
| **How it works** | OAuth flow with Claude.ai credentials |
| **Billing** | Flat subscription fee ($20-100/month) |
| **Registration** | ❌ Not available for third-party apps |
| **Feasibility** | ❌ Blocked by Anthropic (Jan 2026) |

**Important:** As of January 2026, Anthropic restricts OAuth tokens to official apps only:
> "This credential is only authorized for use with Claude Code and cannot be used for other API requests."

### Conclusion
For a custom UI app, **API Key authentication is the only viable option**. Users would need to pay for API usage separately from any Pro/Max subscription.

However, the **hybrid approach** sidesteps this entirely by using Claude CLI (which supports Pro/Max subscriptions) as the backend.

---

## Architecture Options

### Option A: Parse Terminal Output (Not Recommended)

```
User Input → Claude CLI (terminal mode) → ANSI Output → Parse → UI
```

- **Effort:** 2-4 weeks
- **Risk:** High (fragile parsing, breaks on CLI updates)
- **Verdict:** ❌ Too fragile

### Option B: Direct Claude API (Full Custom App)

```
User Input → Anthropic API → Tool Execution → UI
```

- **Effort:** 4-8 weeks
- **Risk:** Low (stable API)
- **Limitation:** Requires API key (no subscription support)
- **Verdict:** ⚠️ Good but requires reimplementing tool execution

### Option C: Hybrid Terminal + JSON Overlay (Recommended)

```
User Input → Claude CLI (stream-json mode) → JSON Events → Parse → UI
                    ↓
              Terminal (hidden/toggle)
```

- **Effort:** 2-3 weeks
- **Risk:** Medium (JSON format undocumented but stable)
- **Benefit:** Works with Pro/Max subscription via CLI
- **Verdict:** ✅ Best balance of effort and capability

---

## Recommended Approach: Hybrid Terminal + Overlay

### How It Works

1. Launch Claude CLI with `--output-format stream-json --input-format stream-json`
2. Parse JSON events from stdout
3. Render messages in custom SwiftUI views
4. Keep terminal available as fallback/debug view

### Visual Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SlothyTerminal                           │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────────────┐ │
│  │   Message List      │    │   Terminal (Hidden/Toggle)  │ │
│  │   ┌─────────────┐   │    │   ┌───────────────────────┐ │ │
│  │   │ User: ...   │   │    │   │ Raw output (fallback) │ │ │
│  │   ├─────────────┤   │    │   │                       │ │ │
│  │   │ Assistant:  │   │    │   └───────────────────────┘ │ │
│  │   │ ```python   │   │    └─────────────────────────────┘ │
│  │   │ def hello() │   │                                    │
│  │   │ ```         │   │    ┌─────────────────────────────┐ │
│  │   ├─────────────┤   │    │   Input Composer            │ │
│  │   │ 🔧 Tool:    │   │    │   [Type your message...]    │ │
│  │   │ Edit file   │   │    └─────────────────────────────┘ │
│  │   └─────────────┘   │                                    │
│  └─────────────────────┘                                    │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

```
User types message
       │
       ▼
┌──────────────────┐
│ Input Composer   │
└────────┬─────────┘
         │ JSON: {"type":"user","message":"..."}
         ▼
┌──────────────────┐
│ Claude CLI       │ --output-format stream-json
│ (PTY Process)    │
└────────┬─────────┘
         │ JSON events (one per line)
         ▼
┌──────────────────┐
│ ClaudeOutputParser│
└────────┬─────────┘
         │ ParsedContent[]
         ▼
┌──────────────────┐
│ ConversationState│
└────────┬─────────┘
         │ @Observable updates
         ▼
┌──────────────────┐
│ MessageListView  │
└──────────────────┘
```

---

## Implementation Plan

### Phase 1: Foundation (Week 1)

#### 1.1 Create Data Models
- [ ] `ParsedContent` enum for all event types
- [ ] `ToolUse` struct for tool calls
- [ ] `ToolResult` struct for tool outputs
- [ ] `ConversationMessage` enum for UI rendering

#### 1.2 Create Output Parser
- [ ] `ClaudeOutputParser` class
- [ ] Line-based JSON parsing
- [ ] Handle all known event types
- [ ] Graceful handling of unknown events

#### 1.3 Create Conversation State
- [ ] `ConversationState` @Observable class
- [ ] Message accumulation
- [ ] Streaming text handling
- [ ] Integration with existing `Tab` model

### Phase 2: UI Components (Week 2)

#### 2.1 Message Views
- [ ] `MessageListView` - scrollable message container
- [ ] `UserMessageView` - user message bubble
- [ ] `AssistantMessageView` - assistant message with markdown
- [ ] `StreamingTextView` - animated streaming text

#### 2.2 Tool Views
- [ ] `ToolUseView` - generic tool call display
- [ ] `EditToolView` - file edit with diff
- [ ] `BashToolView` - command execution
- [ ] `ReadToolView` - file read display
- [ ] `ToolResultView` - tool output display

#### 2.3 Input Components
- [ ] `InputComposer` - multi-line text input
- [ ] Keyboard shortcuts (Enter to send, Shift+Enter for newline)
- [ ] Command history support

### Phase 3: Integration (Week 3)

#### 3.1 Agent Modifications
- [ ] Add `supportsJsonOutput` to `AIAgent` protocol
- [ ] Modify `ClaudeAgent` to use `--output-format stream-json`
- [ ] Create `ClaudeJsonAgent` variant if needed

#### 3.2 View Integration
- [ ] Create `HybridTerminalView` combining both UIs
- [ ] Add toggle between message/terminal views
- [ ] Wire up to existing tab system

#### 3.3 Polish
- [ ] Markdown rendering with syntax highlighting
- [ ] Copy code button for code blocks
- [ ] Collapsible tool results
- [ ] Error state handling

### Phase 4: Testing & Refinement (Ongoing)

- [ ] Test with various Claude responses
- [ ] Handle edge cases (long outputs, errors)
- [ ] Performance optimization for large conversations
- [ ] User preference persistence

---

## Technical Details

### Claude CLI JSON Event Types

Based on testing, Claude CLI outputs these JSON event types:

```json
// Final result (end of response)
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 2268,
  "num_turns": 1,
  "result": "...",
  "session_id": "uuid",
  "total_cost_usd": 0.0461625,
  "usage": {
    "input_tokens": 2,
    "output_tokens": 5,
    ...
  }
}

// Content block delta (streaming text)
{
  "type": "content_block_delta",
  "delta": {
    "type": "text_delta",
    "text": "partial text..."
  }
}

// Tool use
{
  "type": "tool_use",
  "id": "tool_use_id",
  "name": "Edit",
  "input": {
    "file_path": "/path/to/file",
    "old_string": "...",
    "new_string": "..."
  }
}

// Tool result
{
  "type": "tool_result",
  "tool_use_id": "tool_use_id",
  "output": "...",
  "is_error": false
}
```

### Key Swift Types

```swift
/// Parsed content from Claude CLI stream-json output
enum ParsedContent {
  case userMessage(String)
  case assistantText(String)
  case assistantThinking(String)
  case toolUse(ToolUse)
  case toolResult(ToolResult)
  case error(String)
  case status(StatusUpdate)
}

/// Tool use details
struct ToolUse: Identifiable {
  let id: String
  let name: String
  let input: [String: Any]

  var toolType: ToolType {
    ToolType(rawValue: name) ?? .unknown
  }
}

enum ToolType: String {
  case edit = "Edit"
  case bash = "Bash"
  case read = "Read"
  case write = "Write"
  case glob = "Glob"
  case grep = "Grep"
  case unknown
}

/// Conversation state manager
@Observable
class ConversationState {
  var messages: [ConversationMessage] = []
  var isStreaming = false
  var currentStreamingText = ""

  private let parser = ClaudeOutputParser()

  func processOutput(_ chunk: String) {
    // Parse and update state
  }
}
```

### File Structure

```
SlothyTerminal/
├── Chat/
│   ├── Models/
│   │   ├── ParsedContent.swift
│   │   ├── ToolUse.swift
│   │   ├── ToolResult.swift
│   │   └── ConversationMessage.swift
│   ├── Parser/
│   │   └── ClaudeOutputParser.swift
│   ├── State/
│   │   └── ConversationState.swift
│   └── Views/
│       ├── MessageListView.swift
│       ├── MessageBubble.swift
│       ├── UserMessageView.swift
│       ├── AssistantMessageView.swift
│       ├── StreamingTextView.swift
│       ├── ToolUseView.swift
│       ├── ToolResultView.swift
│       ├── InputComposer.swift
│       └── HybridTerminalView.swift
```

---

## Risks and Mitigations

### Risk 1: stream-json Format Changes

**Risk:** Claude CLI's JSON format is not officially documented and may change.

**Mitigation:**
- Add fallback to terminal-only mode if parsing fails
- Log unparsed events for debugging
- Design parser to handle unknown event types gracefully
- Pin Claude CLI version in documentation

### Risk 2: Complex Tool Outputs

**Risk:** Some tool outputs (large diffs, binary content) may be hard to display.

**Mitigation:**
- Truncate large outputs with "Show more" button
- Provide "View in terminal" option
- Use collapsible sections for verbose content

### Risk 3: Performance with Large Conversations

**Risk:** Long conversations may cause UI lag.

**Mitigation:**
- Use `LazyVStack` for message list
- Implement virtualization for very long conversations
- Add "Clear conversation" option

### Risk 4: Input Format Compatibility

**Risk:** `--input-format stream-json` may have specific requirements.

**Mitigation:**
- Test thoroughly with various input types
- Fall back to sending raw text if JSON input fails
- Document any input format quirks

---

## Dependencies

### Required
- None (uses existing SwiftUI and Foundation)

### Recommended
- [swift-markdown](https://github.com/apple/swift-markdown) - For markdown rendering
- [Highlightr](https://github.com/raspu/Highlightr) - For syntax highlighting (optional)

### Existing (Already in Project)
- SwiftTerm - Terminal emulation (kept for fallback)
- Existing `StatsParser` patterns - Reusable for JSON parsing

---

## Success Criteria

1. **Functional:** Messages display correctly in chat UI
2. **Streaming:** Text streams in real-time as Claude responds
3. **Tools:** Tool calls display with appropriate visualizations
4. **Fallback:** Terminal view remains accessible
5. **Performance:** No lag with 100+ message conversations
6. **Compatibility:** Works with Claude CLI's Pro/Max subscription

---

## References

- [Claude Code Authentication Docs](https://code.claude.com/docs/en/authentication)
- [Anthropic API Overview](https://platform.claude.com/docs/en/api/overview)
- [SwiftTerm GitHub](https://github.com/migueldeicaza/SwiftTerm)
- [libghostty Announcement](https://mitchellh.com/writing/libghostty-is-coming)

---

## Appendix: Alternative - Direct API Implementation

If the hybrid approach proves insufficient, a full API-based implementation would require:

| Component | Effort | Notes |
|-----------|--------|-------|
| API Key Input/Storage | 1-2 days | macOS Keychain |
| Anthropic API Client | 2-3 days | Messages API, streaming |
| Tool Definitions | 1-2 days | Match Claude Code tools |
| Tool Execution | 1-2 weeks | Bash, file ops, safety |
| Conversation Management | 3-5 days | Context, history |
| **Total** | **4-6 weeks** | Full reimplementation |

This approach requires API key (no subscription support) but provides complete control over the experience.
