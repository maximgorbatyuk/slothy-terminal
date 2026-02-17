# Changelog

All notable changes to SlothyTerminal will be documented in this file.

## [2026.2.5] - 2026-02-17

### Added
- **Task Queue** - Background AI task execution engine for running prompts headlessly without occupying a chat tab.
  - Compose tasks with title, prompt, agent type (Claude or OpenCode), working directory, and priority (High/Normal/Low).
  - Priority-then-FIFO scheduling with sequential execution.
  - Live log streaming with timestamped entries (capped at 500 lines in UI, 5MB per log artifact).
  - Per-task log artifacts persisted to `~/Library/Application Support/SlothyTerminal/tasks/logs/`.
  - Auto-retry with exponential backoff (2s/4s/8s) for transient failures; permanent failures (CLI not found, empty prompt) fail immediately.
  - 30-minute execution timeout per task.
  - Preflight validation: checks prompt non-empty, repo path exists, agent supports chat mode, CLI is installed.
  - Crash recovery: tasks stuck in `.running` state at app restart are reset to `.pending` with an interrupted note.
  - Persistent queue stored at `~/Library/Application Support/SlothyTerminal/tasks/queue.json` with schema versioning.
- **Risky Tool Detection** - Post-execution approval gate for dangerous operations detected during headless task runs.
  - Bash tool checks: `git push`, `git commit`, `rm -rf`, `rm -r`, SQL `DROP`/`DELETE FROM`/`TRUNCATE`, `sudo`, `chmod`, `chown`.
  - Write tool checks: `.env` files, `credentials` paths, `.ssh/` directory, `.gitconfig`, GitHub Actions workflows.
  - Tasks with detected risky operations pause the queue and show an approval banner (Approve / Reject / Review).
- **Task Queue UI** - Full panel and modal views for managing the queue.
  - Sidebar panel with running, pending, and collapsible history sections.
  - Real-time status summary (idle/running indicator + pending count).
  - Orange approval banner when a task awaits human review.
  - Task composer modal with agent picker, working directory selector, and priority.
  - Task detail modal with full metadata, prompt, result summary, risky operations, error info, live log, and persisted log artifact.
  - Task row with animated status pulse, live log line preview, and context-menu actions (Copy Title/Prompt, Retry, Cancel, Remove).
- **Libghostty Terminal Backend** - Replaced SwiftTerm + PTYController with libghostty for GPU-accelerated terminal rendering.
  - `GhosttyApp` singleton manages the process-wide libghostty app instance, config loading (uses Ghostty's standard config files), and C callback routing.
  - `GhosttySurfaceView` is a full `NSView` + `NSTextInputClient` implementation per terminal tab: IME support with preedit/composition, keyboard/mouse/scroll/pressure forwarding, cursor shape updates, clipboard integration, and renderer health monitoring.
  - Metal-accelerated rendering via `GhosttyKit.xcframework`.
  - Deferred surface creation pattern (`pendingLaunchRequest`) for SwiftUI lifecycle compatibility.
  - Single-source size updates from `layout()` only, preventing duplicate SIGWINCH during startup.
  - Window occlusion tracking for renderer throttling.
  - PUA range filtering (0xF700-0xF8FF) for macOS function key codes.
  - Right-side modifier key detection via raw `NX_DEVICE*` flags.
- **OpenCode Ask Mode** - Instructs the agent to ask clarifying questions before implementing.
  - Toggle persisted across sessions via `lastUsedOpenCodeAskModeEnabled` config field.
  - Blue badge in chat input when active: "Ask mode active: agent asks clarifying questions first".
  - Directive prepended to every user message when enabled.
- **Claude CLI Mach-O Path Resolution** - `ClaudeAgent.command` now resolves the full executable path, preferring native Mach-O binaries over Node.js script wrappers.
  - Two-pass search: first for Mach-O binaries (checks magic bytes after resolving symlinks), then any executable.
  - Search order prioritizes `~/.local/bin/claude` over `/opt/homebrew/bin/claude`.
  - `~/.local/bin` added to terminal PATH defaults.
- **AppConfig Enhancements**
  - `terminalInteractionMode` (Host Selection / App Mouse) for controlling mouse input routing in TUI tabs.
  - `chatShowTimestamps` and `chatShowTokenMetadata` toggles for per-message metadata visibility.
  - `chatMessageTextSize` (Small / Medium / Large) controlling body and metadata font sizes.
  - `claudeAccentColor` and `opencodeAccentColor` for per-agent custom colors via `CodableColor` wrapper.
  - `claudePath` and `opencodePath` for custom CLI path overrides.
- **Chat Input History Navigation** - Up/down arrow keys navigate previously sent messages.
- **Chat Suggestion Chips** - Empty state shows quick-start prompts (Review codebase, Fix tests, Explain architecture, Help refactor).
- **Chat Activity Bar** - Context-aware streaming indicator: "Running `<toolName>`..." when a tool is active.
- **New tests** - `RiskyToolDetectorTests`, `TaskLogCollectorTests`, `TaskOrchestratorTests`, `TaskQueueStateTests`, `TaskQueueStoreTests`, `MockTaskRunner`.

### Changed
- Terminal rendering backend switched from SwiftTerm to libghostty (Metal-accelerated).
- `PTYController` deleted; PTY management now handled by libghostty's embedded runtime.
- SwiftTerm SPM dependency removed.
- macOS minimum raised to 15.0; Zig 0.14+ and Ghostty source required for building.
- `GhosttyKit.xcframework` must be present in the project root for Xcode builds.
- `Tab` model simplified: removed `ptyController`, `localTerminalView`, `terminalViewID`, `statsParserTask` properties.
- Sidebar gains a Tasks tab for the task queue panel.
- `isAvailable()` in `ClaudeAgent` now checks `~/.local/bin/claude` before `/opt/homebrew/bin/claude`.

### Fixed
- **IME candidate window positioning** - `characterIndex(for:)` now returns `NSNotFound` instead of `0`.
- **Ghostty callback nil safety** - `ghosttyWakeup` guards against nil `userdata` instead of force-unwrapping.
- **Task queue crash recovery** - Tasks with `.running` status at app restart are reset to `.pending`.
- **Risky tool pattern matching** - SQL patterns (`DROP`, `DELETE FROM`, `TRUNCATE`) are now consistently lowercase to match the lowercased input; removed redundant `.lowercased()` call.
- **Terminal prompt duplication** - Fixed multiple `sizeDidChange` calls during startup by making `layout()` the single source of truth for size updates, matching Ghostty's architecture.

### Docs
- Added `Terminal Environment Variables` section to `CLAUDE.md`.
- Added `messageForCLI` doc comment documenting directive injection consideration in OpenCode transport.
- Expanded PUA range comment with `NSEvent.h` reference.

## [2026.2.4] - 2026-02-10

### Added
- **Production chat engine architecture** with explicit state machine (`idle/sending/streaming/cancelling/recovering/...`), typed session commands/events, and transport abstraction.
- **Native OpenCode Chat** (non-TUI) with structured JSON stream parsing, event mapping, tool-use rendering, and session continuity.
- **Chat persistence layer** (`ChatSessionStore`) with per-session snapshots for restoring conversations, usage, selected model/mode, and metadata.
- **Richer chat rendering**:
  - Custom markdown block renderer (headings, lists, code blocks, inline markdown).
  - Tool-specific views (bash, file, edit, search, generic fallback).
  - Reusable copy button component and improved message block handling.
- **Composer status bar** below chat input with provider-aware controls:
  - Mode selection (Build/Plan).
  - Model selection.
  - Selected vs resolved metadata display.
- **Searchable OpenCode model picker** populated dynamically from `opencode models`, grouped by provider prefix (for example `anthropic`, `openai`, `github-copilot`, `zai`).
- **Extensive test coverage** for new chat stack:
  - Engine transitions and tool-use flow.
  - Claude/OpenCode parser behavior.
  - Session storage roundtrip.
  - Mock transport support.

### Changed
- Chat stack refactored from monolithic `ChatState` behavior to engine + transport + storage layering.
- Tab labels now use mode-oriented naming:
  - `Claude | chat`, `Claude | cli`, `Opencode | chat`, `Opencode | cli`, `Terminal | cli`.
- Window title format updated to: `📁 <directory-name> | Slothy Terminal`.
- Window chrome adjusted to a thinner, compact native title bar style (Ghostty-like direction) without custom rounded title blocks.
- OpenCode chat remembers last used model and mode across new tabs and restarts.

### Fixed
- **Claude stream-json tool turn handling**:
  - No longer finalizes turn on intermediate `message_stop`.
  - Correctly handles multi-segment turns (`tool_use -> tool_result -> continued assistant output -> result`).
- **Claude parser compatibility fixes**:
  - Added support for `input_json_delta.delta.partial_json`.
  - Added support for tool names from `content_block_start.content_block.name`.
  - Added support for top-level `type: "user"` `tool_result` events.
- OpenCode Build/Plan mode argument mapping corrected (Build now maps to `--agent build`).
- OpenCode transport no longer emits empty session IDs on initial readiness.
- Removed stale/invalid model IDs from chat model selection defaults.

### Docs
- Added `Chat Engine Notes` to `CLAUDE.md` documenting Claude stream-json multi-segment behavior and parser/state-machine requirements.
- Added implementation planning docs for merged chat architecture and OpenCode support.

## [2026.2.3] - 2026-02-05

### Added
- **Chat UI (Beta)** - Native SwiftUI chat interface communicating with Claude CLI via persistent `Foundation.Process` with bidirectional `stream-json`
  - Streaming message display with thinking, tool use, and tool result content blocks
  - Markdown rendering toggle (Markdown / Plain text) in status bar
  - Configurable send key: Enter or Shift+Enter (the other inserts a newline)
  - Smart Claude path resolution preferring standalone binary over npm wrapper
  - Session persistence across messages via `--include-partial-messages`
  - Auto-scroll to latest content during streaming
  - Expandable/collapsible tool use and tool result blocks
  - Empty state with usage hints, error banner with dismiss
  - Chat sidebar showing message count, session duration, and token usage (input/output)
  - Dedicated tab icon and "Chat β" prefix in tab bar
  - Beta labels on all chat UI entry points
  - Menu item "New Claude Chat (Beta)" with keyboard shortcut `Cmd+Shift+Option+T`
  - `ChatTabTypeButton` on the empty terminal welcome screen
- **Saved Prompts** - Reusable prompts that can be attached when opening AI agent tabs
  - Create, edit, and delete prompts in the new Prompts settings tab
  - Prompt picker in folder selector and agent selection modals
  - Safe flag termination with `--` to prevent prompt text from being parsed as CLI flags
  - Agent-specific prompt passing: Claude uses `--`, OpenCode uses `--prompt`, Terminal ignores prompts
  - 10,000-character limit enforced in the editor
- **Configuration File section in General settings** - Shows the config file path and quick-open buttons for installed editors (VS Code, Cursor, Antigravity)
- `PROMPTS.md` documentation for built-in reusable prompts

### Fixed
- **PTY process cleanup on app quit** - Added `terminateAllSessions()` called via `NSApplication.willTerminateNotification` to ensure all child processes are terminated
- **PTY resource management overhaul**
  - Added `ProcessResourceHolder` for thread-safe access to child PID and master FD from any isolation context
  - Added `deinit` safety net on `PTYController` to clean up leaked processes
  - `terminate()` now closes the master FD first (triggering kernel SIGHUP), signals the entire process group (`kill(-pid, ...)`), and polls up to 100 ms before force-killing
  - Fixed zombie processes: added `waitpid` reaping on EOF and read-error paths in the read loop
- **External app opening** - Fixed `ExternalAppManager` to use `NSWorkspace.shared.open(_:withApplicationAt:)` instead of `openApplication(at:)`, correctly passing the target URL
- **Text selection in terminal** - Disabled mouse reporting (`allowMouseReporting = false`) so text selection works instead of forwarding mouse events to the child process (e.g., Claude CLI)

### Changed
- Version bumped to 2026.2.3
- `Tab` model now supports a `TabMode` (`.terminal` / `.chat`) and holds an optional `ChatState`
- `AppState` terminates chat processes alongside PTY sessions on tab close and app quit
- `shortenedPath()` helper refactored to accept `String` instead of `URL`
- Removed `claude-custom-ui.md` planning document (superseded by implementation)

## [2026.2.2] - 2026-02-03

### Added
- **Directory Tree in Sidebar** - Collapsible file browser showing project structure
  - Displays files and folders with system icons
  - Shows hidden files (.github, .claude, .gitignore, etc.)
  - Folders first, then files, both sorted alphabetically
  - Double-click any item to copy relative path to clipboard
  - Right-click context menu with:
    - Copy Relative Path
    - Copy Filename
    - Copy Full Path
  - Lazy-loads subdirectories on expand for performance
  - Limited to 100 visible items to prevent slowdowns
- **Open in External Apps** - Quick-access dropdown to open working directory in installed apps
  - Finder (opens folder directly)
  - Claude Desktop
  - ChatGPT
  - VS Code
  - Cursor
  - Xcode
  - Rider, IntelliJ, Fleet
  - iTerm, Warp, Ghostty, Terminal
  - Sublime Text, Nova, BBEdit, TextMate
- GitHub Actions CI workflow for automated builds and tests
- Unit tests for AgentFactory, StatsParser, UsageStats, and RecentFoldersManager
- Swift Package Manager support (Package.swift)
- Privacy policy documentation (PRIVACY.md)

### Changed
- Improved sidebar layout with directory tree below "Open in..." button
- Enhanced working directory card display

## [2026.2.1] - 2026-02-02

### Added
- Automatic update support via Sparkle framework
- "Check for Updates" menu item
- Updates section in Settings with auto-check toggle
- Release build script with notarization
- Appcast feed for update distribution

### Changed
- Build script now reads credentials from `.env` file
- Updated release workflow documentation
