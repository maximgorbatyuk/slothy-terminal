# Changelog

All notable changes to SlothyTerminal will be documented in this file.

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
  - `Claude | chat`, `Opencode | chat`, `Claude | cli`, `Opencode | cli`.
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
