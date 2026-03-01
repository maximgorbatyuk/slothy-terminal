# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SlothyTerminal is a native macOS terminal application (Swift/SwiftUI) for AI coding assistants. It features a tabbed interface supporting Claude CLI, OpenCode CLI, and plain terminal sessions with real-time session statistics. OpenCode is the primary smart backend for multi-provider model access.

- **Platform:** macOS 14.0+ (SPM), macOS 15.0 (Xcode deployment target)
- **Language:** Swift 5.9+
- **Build System:** Xcode 15.0+ with SPM

## Project reference

The app SlothyTerminal combines terminal and AI agent system like opencode and openclaw do. Source code of the apps:

- opencode: `~/projects/opencode`
- openclaw: `~/projects/openclaw`


## Build Commands

```bash
# Open in Xcode (then Cmd+R to build/run)
open SlothyTerminal.xcodeproj

# SPM build & test (chat core, parsers, engine — no UI)
swift build
swift test
# NOTE: Package.swift uses an explicit `sources:` list for the main library target (SlothyTerminalLib).
# New non-UI source files must be added to that list manually or swift build/test will fail.
# The test target auto-discovers files — no manual list needed for new tests.

# Release build with notarization (requires .env with Apple credentials)
./scripts/build-release.sh [VERSION]
# Example: ./scripts/build-release.sh 2026.2.2
```

## Architecture

### Core Data Flow

```
Terminal/CLI Tabs
User Action → AppState.createTab() → Tab (with AIAgent)
                                        ↓
                              GhosttyApp.shared (libghostty runtime)
                                        ↓
                         GhosttySurfaceView spawns PTY via libghostty
                                        ↓
                              Terminal output → StatsParser → UsageStats
                                        ↓
                              TerminalView renders via libghostty surface

Chat Tabs (Claude/OpenCode)
User Action → AppState.createChatTab() → Tab(mode: .chat, ChatState)
                                        ↓
                                  ChatState.sendMessage()
                                        ↓
                          ChatSessionEngine handles lifecycle state
                                        ↓
          Transport: ClaudeCLITransport | OpenCodeCLITransport
                                        ↓
                         Stream parser → Engine events/commands
                                        ↓
                     ChatConversation update + snapshot persistence
                                        ↓
                        ChatView/MessageBubble render markdown/tools
```

### Key Components

- **AppState** (`App/AppState.swift`) - @Observable global state: tabs, active tab, sidebar, modals
- **Tab** (`Models/Tab.swift`) - Session model supporting `.terminal`, `.chat`, and `.telegramBot` modes
- **GhosttyApp** (`Terminal/GhosttyApp.swift`) - Process-wide singleton managing the libghostty app instance and runtime callbacks
- **GhosttySurfaceView** (`Terminal/GhosttySurfaceView.swift`) - NSView bridge to libghostty terminal surface; handles PTY, rendering, and input
- **AIAgent protocol** (`Agents/AIAgent.swift`) - Defines agent interface; implementations: ClaudeAgent, OpenCodeAgent, TerminalAgent
- **AgentFactory** (in `Agents/AIAgent.swift`) - Creates appropriate agent instance based on AgentType enum
- **ConfigManager** (`Services/ConfigManager.swift`) - Singleton for persisting config to `~/Library/Application Support/SlothyTerminal/config.json`
- **ChatState** (`Chat/State/ChatState.swift`) - View-facing coordinator: user intents, transport wiring, persistence triggers, model/mode UI state
- **ChatSessionEngine** (`Chat/Engine/ChatSessionEngine.swift`) - Provider-agnostic chat state machine and event reducer
- **ChatTransport** (`Chat/Transport/ChatTransport.swift`) - Transport protocol for provider backends
- **ClaudeCLITransport** (`Chat/Transport/ClaudeCLITransport.swift`) - Claude stream-json process transport
- **OpenCodeCLITransport** (`Chat/OpenCode/OpenCodeCLITransport.swift`) - OpenCode JSON event process transport
- **ChatSessionStore** (`Chat/Storage/ChatSessionStore.swift`) - Snapshot persistence and restore for chat sessions

### Adding a New Agent (Terminal/CLI Tabs)

1. Create struct conforming to `AIAgent` protocol in `Agents/`
2. Implement: `command`, `defaultArgs`, `environmentVariables`, `contextWindowLimit`, `parseStats()`, `isAvailable()`
3. Add case to `AgentType` enum
4. Update `AgentFactory.createAgent()`
5. Audit all exhaustive `switch` on `AgentType` — files include: `ConfigManager.swift`, `ChatComposerStatusBar.swift`, `TaskOrchestrator.swift`, `TelegramPromptExecutor.swift`, `TaskInjectionRouter.swift`

## Core Architecture Notes

- Keep **terminal agents** and **chat transports** conceptually separate:
  - `AIAgent` is for PTY/CLI tab behavior.
  - `ChatTransport` is for structured CLI-backed chat mode.
- For any new chat-capable CLI backend, prefer this layering:
  1. CLI event model/parser
  2. CLI transport implementing `ChatTransport`
  3. Mapper into `ChatSessionEngine` events
  4. Reuse existing message/tool rendering blocks
- Do not couple UI directly to CLI JSON shapes; normalize through engine events first.
- Persist session metadata early (session id, selected model/mode) to ensure recovery after crashes/relaunch.
- Provider/model capabilities come through OpenCode CLI (`opencode models`, `opencode export`).

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

- **GhosttyKit** (xcframework) - Terminal emulation, PTY, and rendering via libghostty (built from source, gitignored)
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

## Known Issues & Pitfalls

- `BuildConfig` uses `fatalError()` on missing config files — should degrade gracefully

## Terminal Environment Variables

When launching terminal sessions, the following environment variables **must** be set to ensure proper shell behavior (cursor movement, line clearing, color support):

- `TERM=xterm-256color` - Tells shell/programs the terminal type for proper escape sequence handling
- `COLORTERM=truecolor` - Indicates 24-bit color support
- `TERM_PROGRAM=SlothyTerminal` - Identifies the terminal emulator
- `TERM_PROGRAM_VERSION` - Version identifier

**Why this matters:** When launched from Finder (not a terminal parent process), `ProcessInfo.processInfo.environment` won't contain these variables. Without them, shells like zsh with fancy prompts (e.g., mathiasbynens/dotfiles) won't properly handle escape sequences like carriage return (`\r`) and clear-line (`\x1b[K`), causing prompt segments to appear on new lines instead of redrawing in place.

These are set in:
- `TerminalView.makeLaunchEnvironment()` - Primary terminal view (also sets `TERM_PROGRAM` / `TERM_PROGRAM_VERSION`)
- `TerminalAgent.environmentVariables` - Plain terminal agent
- `ClaudeAgent.environmentVariables` / `OpenCodeAgent.environmentVariables` - AI agent tabs

## TaskQueue Subsystem

Background task execution with preflight checks and log collection.

- **QueuedTask** (`TaskQueue/Models/QueuedTask.swift`) - Task model with status, prompt, agent binding
- **TaskQueueState** (`TaskQueue/State/TaskQueueState.swift`) - @Observable queue state
- **TaskOrchestrator** (`TaskQueue/Orchestrator/TaskOrchestrator.swift`) - Schedules and dispatches queued tasks
- **TaskPreflight** (`TaskQueue/Orchestrator/TaskPreflight.swift`) - Pre-execution validation
- **TaskRunner** (`TaskQueue/Runner/TaskRunner.swift`) - Protocol; implementations: `ClaudeTaskRunner`, `OpenCodeTaskRunner`
- **TaskInjectionRouter** (`TaskQueue/Runner/TaskInjectionRouter.swift`) - Injection-first execution: routes task prompts to matching open terminal tabs before falling back to headless runners
- **TaskInjectionProvider** (protocol in `TaskInjectionRouter.swift`) - Testable abstraction for tab lookup and injection submission; `AppState` conforms
- **RiskyToolDetector** (`TaskQueue/Runner/RiskyToolDetector.swift`) - Flags potentially destructive tool calls
- **TaskLogCollector** (`TaskQueue/Runner/TaskLogCollector.swift`) - Captures task execution logs
- **TaskQueueSnapshot** (`TaskQueue/Storage/TaskQueueSnapshot.swift`) - Codable snapshot models for queue state
- **TaskQueueStore** (`TaskQueue/Storage/TaskQueueStore.swift`) - Snapshot persistence (same pattern as ChatSessionStore)

### Task Execution: Injection-First Routing

When `TaskOrchestrator` executes a task, it attempts injection before headless execution:

1. Preflight validation (rejects `.terminal`, verifies CLI, checks repoPath)
2. **Injection attempt** via `TaskInjectionRouter`: finds a matching open terminal tab (`mode == .terminal`, same `agentType`, same working directory, registered surface). Prefers active tab.
3. If injected: task completes immediately with a summary directing user to the tab.
4. If no match or injection fails: falls back to headless `ClaudeTaskRunner`/`OpenCodeTaskRunner`.

The `TaskInjectionProvider` protocol keeps injection logic testable in SwiftPM without `AppState`.

## Injection Subsystem

Programmatic input injection into live terminal surfaces. Used by TaskQueue for injection-first routing and available for UI/Telegram/external API use.

- **InjectionPayload** (`Injection/Models/InjectionPayload.swift`) - Content types: `.command`, `.text`, `.paste`, `.control`, `.key`
- **InjectionRequest** (`Injection/Models/InjectionRequest.swift`) - Request envelope with target, origin, status, timeout
- **InjectionTarget** (`Injection/Models/InjectionTarget.swift`) - `.activeTab`, `.tabId(UUID)`, `.filtered(agentType:mode:)`
- **InjectionOrchestrator** (`Injection/Orchestrator/InjectionOrchestrator.swift`) - Per-tab FIFO queues, timeout handling, "worst wins" status escalation
- **TerminalSurfaceRegistry** (`Injection/Registry/TerminalSurfaceRegistry.swift`) - Weak-ref map of tab IDs to live `InjectableSurface` instances (GhosttySurfaceView)
- **InjectionTabProvider** (protocol in `InjectionOrchestrator.swift`) - Tab lookup abstraction; `AppState` conforms
- **InjectionEvent** / **InjectionResult** - Observable lifecycle events and per-tab outcome models

`AppState` exposes `inject(_:)`, `cancelInjection(id:)`, and `listInjectableTabs()` for callers. `GhosttySurfaceView` registers/unregisters itself with `TerminalSurfaceRegistry` on create/destroy.

## Telegram Bot Subsystem

Tab mode `.telegramBot` enables a Telegram bot that relays messages to a Claude chat session.

- **TelegramBotRuntime** (`Telegram/Runtime/TelegramBotRuntime.swift`) - Long-poll loop, message dispatch
- **TelegramCommandHandler** (`Telegram/Runtime/TelegramCommandHandler.swift`) - Slash command parsing and execution
- **TelegramPromptExecutor** (`Telegram/Runtime/TelegramPromptExecutor.swift`) - Bridges Telegram messages into chat engine turns
- **TelegramBotAPIClient** (`Telegram/API/TelegramBotAPIClient.swift`) - Telegram Bot API HTTP client
- **TelegramMessageChunker** (`Telegram/API/TelegramMessageChunker.swift`) - Splits long messages for Telegram's size limits
- Settings UI in `Views/Settings/TelegramSettingsTab.swift`
