# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SlothyTerminal is a native macOS terminal application (Swift/SwiftUI) for AI coding assistants. It features a tabbed interface supporting Claude CLI, OpenCode, and plain terminal sessions with real-time session statistics.

- **Platform:** macOS 13.0+
- **Language:** Swift 5.9+
- **Build System:** Xcode 15.0+ with SPM

## Build Commands

```bash
# Open in Xcode (then Cmd+R to build/run)
open SlothyTerminal.xcodeproj

# Release build with notarization (requires .env with Apple credentials)
./scripts/build-release.sh [VERSION]
# Example: ./scripts/build-release.sh 2026.2.2
```

## Architecture

### Core Data Flow

```
Terminal/CLI Tabs
User Action → AppState.createTab() → Tab (with AIAgent + PTYController)
                                        ↓
                                   PTYController.spawn() via forkpty()
                                        ↓
                              Terminal output → StatsParser → UsageStats
                                        ↓
                              TerminalView renders via SwiftTerm

Chat Tabs (Claude/OpenCode)
User Action → AppState.createChatTab() → Tab(mode: .chat, ChatState)
                                        ↓
                                  ChatState.sendMessage()
                                        ↓
                          ChatSessionEngine handles lifecycle state
                                        ↓
                  Transport (ClaudeCLITransport/OpenCodeCLITransport)
                                        ↓
                         Stream parser → Engine events/commands
                                        ↓
                     ChatConversation update + snapshot persistence
                                        ↓
                        ChatView/MessageBubble render markdown/tools
```

### Key Components

- **AppState** (`App/AppState.swift`) - @Observable global state: tabs, active tab, sidebar, modals
- **Tab** (`Models/Tab.swift`) - Session model supporting `.terminal` and `.chat` modes; owns PTY or ChatState depending on mode
- **PTYController** (`Terminal/PTYController.swift`) - PTY management via POSIX forkpty(), reads output in background Task
- **AIAgent protocol** (`Agents/AIAgent.swift`) - Defines agent interface; implementations: ClaudeAgent, OpenCodeAgent, TerminalAgent
- **AgentFactory** - Creates appropriate agent instance based on AgentType enum
- **ConfigManager** (`Services/ConfigManager.swift`) - Singleton for persisting config to `~/Library/Application Support/SlothyTerminal/config.json`
- **ChatState** (`Chat/State/ChatState.swift`) - View-facing coordinator: user intents, transport wiring, persistence triggers, model/mode UI state
- **ChatSessionEngine** (`Chat/Engine/ChatSessionEngine.swift`) - Provider-agnostic chat state machine and event reducer
- **ChatTransport** (`Chat/Transport/ChatTransport.swift`) - Transport protocol for provider backends
- **ClaudeCLITransport** (`Chat/Transport/ClaudeCLITransport.swift`) - Claude stream-json process transport
- **OpenCodeCLITransport** (`Chat/OpenCode/OpenCodeCLITransport.swift`) - OpenCode JSON event process transport
- **ChatSessionStore** (`Chat/Storage/ChatSessionStore.swift`) - Snapshot persistence and restore for chat sessions

### Adding a New Agent

1. Create struct conforming to `AIAgent` protocol in `Agents/`
2. Implement: `command`, `defaultArgs`, `environmentVariables`, `contextWindowLimit`, `parseStats()`, `isAvailable()`
3. Add case to `AgentType` enum
4. Update `AgentFactory.createAgent()`

## Core Architecture Notes for Agents

- Keep **terminal agents** and **chat transports** conceptually separate:
  - `AIAgent` is for PTY/CLI tab behavior.
  - `ChatTransport` is for structured native chat mode.
- For any new chat-capable provider, prefer this layering:
  1. Provider event model/parser
  2. Provider transport implementing `ChatTransport`
  3. Mapper into `ChatSessionEngine` events
  4. Reuse existing message/tool rendering blocks
- Do not couple UI directly to provider JSON shapes; normalize through engine events first.
- Persist session metadata early (session id, selected model/mode) to ensure recovery after crashes/relaunch.

## Swift Style Guidelines

**Use the `/developing-with-swift` skill before writing Swift code.**
**Use the `/frontend-design` skill before writing *.html, *.css, *.js files.**

Key rules:
- 2 spaces indentation, no tabs
- `guard` clauses must be multi-line with blank line after
- Multi-condition `if` blocks: opening brace on own line
- `case` blocks followed by blank line
- Use `///` for documentation comments, `//` only for MARK/TODO directives
- Use `@Observable` (not ObservableObject) for shared state
- Use `async/await` and `.task` modifier for async work; avoid Combine
- Don't create ViewModels for every view or add unnecessary abstractions
- Any potentially blocking operations (Process, network, file I/O) must be called within `Task { }` in views and marked `async` in services
  - Example: `Task { files = await GitService.shared.getModifiedFiles(in: directory) }`

## Dependencies

- **SwiftTerm** (1.5.1) - Terminal emulation and PTY handling
- **Sparkle** (2.8.1) - Automatic updates framework

## Chat Engine Notes

- Claude `-p --input-format stream-json --output-format stream-json` can emit multiple assistant segments in one user turn:
  `tool_use` -> `message_stop` -> top-level `user` `tool_result` -> more assistant output -> final `result`.
- Do **not** treat `message_stop` as full turn completion. Only finalize the turn on terminal `result` (or explicit terminal error/cancel).
- Parser must support:
  - `content_block_delta.delta.partial_json` for `input_json_delta`
  - `content_block_start.content_block.name` for tool names
  - top-level `type: "user"` events carrying `tool_result`
- If these are mishandled, chat appears to "hang" after tool use even though Claude is still streaming valid events.

### OpenCode chat specifics

- OpenCode chat uses `opencode run --format json` per turn and maps events into engine-compatible events.
- Do not treat intermediate completion (`tool-calls`) as final turn completion; finalize only on terminal stop.
- OpenCode model catalog for UI should come from `opencode models` (dynamic), not hardcoded model lists.
- OpenCode metadata reconciliation (resolved provider/model/mode) can be refreshed from `opencode export <sessionId>`.

## Known Issues (from findings.md)

Critical items to be aware of:
- `BuildConfig` uses `fatalError()` on missing config files - should degrade gracefully
- Force unwraps in `ConfigManager` can crash in edge cases
- `PTYController` uses `nonisolated(unsafe)` for outputContinuation, bypassing concurrency safety
- PTY layer still has less direct test coverage than parser/engine/store chat layers
