# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SlothyTerminal is a native macOS terminal application (Swift/SwiftUI) for AI coding assistants. It features a tabbed interface supporting Claude CLI, OpenCode CLI, and plain terminal sessions with real-time session statistics. OpenCode is the primary smart backend for multi-provider model access.

- **Platform:** macOS 14.0+ (SPM), macOS 15.0 (Xcode deployment target)
- **Language:** Swift 5.9+
- **Build System:** Xcode 15.0+ with SPM

## Build Commands

```bash
# Open in Xcode (then Cmd+R to build/run)
open SlothyTerminal.xcodeproj

# Xcode CLI build (no signing — for verification without certs)
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO

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
- **Tab** (`Models/Tab.swift`) - Session model supporting `.terminal` and `.chat` modes
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
- **Workspace** (`Models/Workspace.swift`) - Groups tabs under a named project directory
- **ScriptScanner** (`Services/PythonScriptScanner.swift`) - Scans for `.py` and `.sh` scripts in project root (shallow) and `scripts/` folder (recursive)
- **GitService** (`Services/GitService.swift`) - Async git operations (modified files, branch info)
- **OpenCodeCLIService** (`Services/OpenCodeCLIService.swift`) - OpenCode CLI wrapper for model catalog and session export
- **UpdateManager** (`Services/UpdateManager.swift`) - Sparkle-based auto-update coordinator (UI-only, excluded from SPM)

### Source Directory Structure

```
SlothyTerminal/
├── Agents/          # AIAgent protocol + implementations (Claude, OpenCode, Terminal)
├── App/             # AppState, AppDelegate, SlothyTerminalApp entry point
├── Chat/            # Chat mode subsystem
│   ├── Engine/      # State machine (ChatSessionEngine)
│   ├── Models/      # ChatMessage, ChatConversation, ToolInput
│   ├── OpenCode/    # OpenCode stream events, parser, mapper, transport
│   ├── Parser/      # Claude stream-json event parser
│   ├── State/       # ChatState (view-facing coordinator)
│   ├── Storage/     # Snapshot persistence (ChatSessionStore)
│   ├── Transport/   # ChatTransport protocol + ClaudeCLITransport
│   └── Views/       # Chat UI (messages, markdown, tools, composer)
├── Injection/       # Terminal input injection (models, orchestrator, registry)
├── Models/          # Tab, Workspace, AppConfig, AgentType, UsageStats
├── Services/        # ConfigManager, GitService, StatsParser, etc.
├── Telegram/        # Telegram bot (API, relay, runtime, models)
├── Terminal/        # GhosttyApp singleton + GhosttySurfaceView
└── Views/           # SwiftUI views (main, sidebar, settings, tab bar)
```

### Adding a New Agent (Terminal/CLI Tabs)

1. Create struct conforming to `AIAgent` protocol in `Agents/`
2. Implement: `command`, `defaultArgs`, `environmentVariables`, `contextWindowLimit`, `parseStats()`, `isAvailable()`
3. Add case to `AgentType` enum
4. Update `AgentFactory.createAgent()`
5. Audit all exhaustive `switch` on `AgentType` — files include: `ConfigManager.swift`, `ChatComposerStatusBar.swift`

### Workspace Architecture

Workspaces are first-class tab containers. Each workspace maps to a project directory and owns a set of tabs.

- `AppState.visibleTabs` — computed property returning only tabs from the active workspace. **All UI code must use `visibleTabs`** (tab bar, terminal container, keyboard shortcuts), not `tabs` directly.
- `AppState.tabs` — global flat list of all tabs across all workspaces. Use only for global operations (terminate all, injection, Telegram).
- `AppState.createWorkspace(from:)` creates an empty workspace (no tab). Creating a workspace calls `switchWorkspace(id:)` to deactivate any current tab.
- `AppState.closeTab(id:)` selects the next tab from the **same workspace**, not globally.
- `AppState.switchWorkspace(id:)` aligns the active tab to the target workspace (first tab, or nil if empty).
- Empty workspaces show `EmptyTerminalView`.

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

## Xcode Project Convention

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` — it auto-discovers source files from the filesystem. **No manual `.pbxproj` edits are needed** when adding new Swift files. Only `Package.swift` requires manual source list updates for new non-UI files.

## Known Issues & Pitfalls

- `BuildConfig` uses `fatalError()` on missing config files — should degrade gracefully
- GhosttyApp C callback trampolines (free functions) cannot be `@MainActor`; helper methods they call must be `nonisolated`
- To open the native Settings window programmatically, use `SettingsLink` (SwiftUI view), not `NSApp.sendAction(Selector(("showSettingsWindow:")))` — the latter logs an error on macOS 14+
- `ModalRouter` in `MainView.swift` maps `ModalType` cases to views — keep it in sync when adding new modal types
- `AppState.pendingSettingsSection` allows pre-selecting a `SettingsSection` tab when the native Settings window opens

## Terminal Environment Variables

Terminal sessions **must** set `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=SlothyTerminal`, and `TERM_PROGRAM_VERSION` — without these, shells launched from Finder mishandle escape sequences (cursor, colors, line clearing).

Set in: `TerminalView.makeLaunchEnvironment()`, `TerminalAgent.environmentVariables`, `ClaudeAgent.environmentVariables`, `OpenCodeAgent.environmentVariables`.

## Injection Subsystem

Programmatic input injection into live terminal surfaces (`Injection/`). `AppState` exposes `inject(_:)`, `cancelInjection(id:)`, and `listInjectableTabs()`. `GhosttySurfaceView` registers/unregisters itself with `TerminalSurfaceRegistry` on create/destroy.

Key types: `InjectionPayload` (`.command`, `.text`, `.paste`, `.control`, `.key`), `InjectionRequest` (envelope with target + origin), `InjectionTarget` (`.activeTab`, `.tabId(UUID)`, `.filtered()`), `InjectionOrchestrator` (per-tab FIFO queues). `AppState` conforms to `InjectionTabProvider`.

### Sidebar Injection Pattern

Follow `PromptsSidebarView` when injecting from sidebar:
1. Check `activeTerminalIsInjectable()` — validates `.terminal` mode tab with registered surface
2. Build `InjectionRequest(payload:target:.activeTab, origin:.ui)`
3. Call `appState.inject(request)` and show status feedback

Payload choice: `.text()` raw insertion, `.paste(_:mode:.bracketed)` multi-line, `.command(_:submit:.insert)` command without execution.

## Telegram Bot Subsystem

Sidebar panel (`.telegram` in `SidebarTab`). Runtime owned by `AppState.telegramRuntime`, decoupled via `TelegramBotDelegate` protocol. Code in `Telegram/` (API client, runtime, relay, models). Settings in `Views/Settings/TelegramSettingsTab.swift`, sidebar in `Views/Telegram/TelegramSidebarView.swift`.

### Telegram Plain Text Routing

When the bot receives plain text (non-slash-command):
1. **Active AI tab** — inject into the active terminal tab if it runs Claude/OpenCode and has a registered surface
2. **Relay fallback** — inject into the active relay session tab (if started via `/relay_start`)
3. **Error reply** — no eligible target; no headless execution for plain text

Slash commands are handled by `TelegramCommandHandler`.

## Testing

```bash
swift test    # Runs all SPM tests (chat engine, parsers, transport, models)
```

- **SPM-testable**: Everything in `Package.swift` `sources:` list — engine, parsers, transports, models, services
- **UI-only** (Xcode only): Views, GhosttyApp, GhosttySurfaceView, UpdateManager, ExternalAppManager
- Test target auto-discovers files in `SlothyTerminalTests/` — no manual list needed for new tests
- Use `MockChatTransport` for engine/state tests without real CLI processes
