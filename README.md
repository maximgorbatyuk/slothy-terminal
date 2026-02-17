# SlothyTerminal

A native macOS terminal application designed for AI coding assistants with a tabbed interface, background task queue, and session tracking.

Privacy-first by design. See the [Privacy Policy](PRIVACY.md).

![macOS](https://img.shields.io/badge/macOS-15.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Overview

SlothyTerminal provides a unified macOS workspace for AI coding agents with:
- native chat tabs (Claude and OpenCode)
- classic CLI/TUI terminal tabs
- a background task queue for headless AI prompt execution

Use Claude CLI, OpenCode, or plain terminal sessions in a clean tabbed interface. Queue prompts for background execution, review risky operations, and track session statistics.

## Features

### Multi-Agent Support
- **Terminal** - Plain shell sessions powered by libghostty (Metal-accelerated)
- **Claude** - Native chat + Claude CLI/TUI tab support
- **OpenCode** - Native chat + OpenCode CLI/TUI tab support

![](/docs/assets/main_window.png)

### Tabbed Interface
- Multiple concurrent sessions
- Quick tab switching with `Cmd+1-9`
- Visual agent indicators with accent colors
- Close tabs with `Cmd+W`
- Mode-aware tab names (`Claude | chat`, `Claude | cli`, `Opencode | chat`, `Opencode | cli`, `Terminal | cli`)

![](/docs/assets/open_new_tab.png)

### Task Queue
- Background AI task execution engine for running prompts headlessly without occupying a chat tab
- Compose tasks with title, prompt, agent type (Claude or OpenCode), working directory, and priority
- Priority-then-FIFO scheduling with sequential execution
- Live log streaming with timestamped entries during task execution
- Log artifacts persisted per task attempt for later review
- Auto-retry with exponential backoff for transient failures (up to 3 retries)
- 30-minute execution timeout per task
- Preflight validation (prompt non-empty, repo exists, CLI installed)
- Crash recovery: tasks interrupted by app restart are automatically reset to pending
- **Risky tool detection**: operations like `git push`, `rm -rf`, writing to `.env`/`.ssh`/credentials are detected and trigger a post-completion approval gate (Approve / Reject / Review)
- Queue panel in the sidebar with running, pending, and history sections
- Task composer modal with agent picker, directory selector, and priority
- Task detail modal with metadata, prompt, result, risky operations, errors, and full log

### GPU-Accelerated Terminal (libghostty)
- Terminal rendering powered by [libghostty](https://github.com/ghostty-org/ghostty), the same engine behind the Ghostty terminal
- Metal-accelerated rendering for smooth, high-performance terminal output
- Full IME support (input method editor) for CJK and other complex input
- Reads Ghostty's standard config files (`~/.config/ghostty/config`) for terminal customization
- Proper keyboard, mouse, scroll, and force-touch event forwarding
- Clipboard integration and cursor shape updates
- Renderer health monitoring and window occlusion throttling

### Session Statistics Sidebar
- Current working directory display
- Session duration timer
- Command counter
- Configurable sidebar position (left/right)

### Native Chat Experience
- Production chat engine architecture (state machine + transport + persistent store)
- Streaming markdown responses with tool-aware rendering
- Reliable multi-step tool flow handling for Claude stream-json
- Session recovery and restore across app restarts
- Composer status bar with mode selection (`Build` / `Plan`), model selection, and resolved metadata
- Context-aware streaming indicator showing active tool name
- Suggestion chips on empty state for quick-start prompts
- Chat input history navigation with up/down arrow keys

### OpenCode Chat Enhancements
- Native OpenCode JSON event transport (`opencode run --format json`)
- Searchable model picker loaded dynamically from `opencode models`
- Model groups by provider prefix (for example `anthropic`, `openai`, `github-copilot`, `zai`)
- Last used OpenCode model/mode remembered for new chats
- **Ask mode**: instructs the agent to ask clarifying questions before implementing, with a visible badge in the input area

### Directory Tree Browser
- Collapsible file tree showing project structure
- Displays files and folders with native system icons
- Shows hidden files (.github, .claude, .gitignore, etc.)
- Sorted display: folders first, then files (alphabetically)
- Double-click to copy relative path to clipboard
- Right-click context menu:
  - Copy Relative Path
  - Copy Filename
  - Copy Full Path
- Lazy-loads subdirectories for performance

### Open in External Apps
- Quick-access dropdown to open working directory in installed apps
- Supports popular development tools:
  - Finder, VS Code, Cursor, Xcode
  - Claude Desktop, ChatGPT
  - iTerm, Warp, Ghostty, Terminal
  - Rider, IntelliJ, Fleet
  - Sublime Text, Nova, BBEdit, TextMate

![](/docs/assets/open_in.png)

### Settings
- **General** - Default agent, sidebar preferences, recent folders
- **Agents** - Custom paths for Claude and OpenCode CLIs
- **Appearance** - Terminal font family and size, agent accent colors, chat message text size
- **Chat** - Markdown rendering mode, send key behavior, message timestamps and token metadata toggles
- **Shortcuts** - View keyboard shortcuts

### Additional Features
- Smart Claude CLI path resolution preferring native Mach-O binaries over Node.js wrappers
- Recent folders quick access
- Automatic updates via Sparkle framework
- Compact native title bar with contextual window title
- Terminal interaction mode (Host Selection for text selection, App Mouse for TUI forwarding)
- Native macOS integration

![](/docs/assets/select_working_folder.png)

## Screenshot

![](/docs/assets/claude.png)

![](/docs/assets/opencode.png)

## Installation

### Download

Download the latest DMG from [GitHub Releases](https://github.com/maximgorbatyuk/slothy-terminal/releases).

1. Open the DMG file
2. Drag SlothyTerminal to Applications
3. Launch from Applications folder

### Requirements

- macOS 15.0 or later
- [Claude CLI](https://claude.ai/code) (optional)
- [OpenCode](https://opencode.ai) (optional)

## Keyboard Shortcuts

### Tabs
| Action | Shortcut |
|--------|----------|
| New Chat Tab (Claude) | `Cmd+T` |
| New Claude TUI Tab | `Cmd+Shift+T` |
| New OpenCode Chat Tab | `Cmd+Option+T` |
| New Terminal Tab | `Cmd+Shift+Option+T` |
| Close Tab | `Cmd+W` |
| Next Tab | `Cmd+Shift+]` |
| Previous Tab | `Cmd+Shift+[` |
| Switch to Tab 1-9 | `Cmd+1` through `Cmd+9` |

### Window
| Action | Shortcut |
|--------|----------|
| Toggle Sidebar | `Cmd+B` |
| Open Folder | `Cmd+O` |
| Settings | `Cmd+,` |

## Configuration

Access settings via `Cmd+,` or **SlothyTerminal → Settings**.

### General Settings
- Default agent for new tabs
- Sidebar visibility and position
- Sidebar width
- Recent folders limit

### Agent Settings
- Custom executable paths for Claude CLI and OpenCode
- Installation verification

### Chat Settings
- Markdown rendering mode (Markdown / Plain)
- Chat send key behavior (Enter vs Shift+Enter)

### Appearance Settings
- Terminal font family (monospaced fonts)
- Terminal font size (10-24pt)
- Custom accent colors for agents

## Building from Source

### Prerequisites

- Xcode 15.0+
- macOS 15.0+
- [Zig](https://ziglang.org/) 0.14+ (`brew install zig`)
- [Ghostty](https://github.com/ghostty-org/ghostty) source code cloned locally

### Dependencies

- [libghostty](https://github.com/ghostty-org/ghostty) - GPU-accelerated terminal rendering (Metal) and PTY management via `GhosttyKit.xcframework`
- [Sparkle](https://github.com/sparkle-project/Sparkle) - Auto-updates (via Swift Package Manager)

### Build

```bash
git clone https://github.com/maximgorbatyuk/slothy-terminal.git
cd slothy-terminal
```

#### 1. Build GhosttyKit.xcframework

The terminal rendering backend is powered by libghostty, which must be built from the Ghostty source repo. This produces a `GhosttyKit.xcframework` containing the static library and Metal shaders.

```bash
# Clone ghostty if you haven't already
git clone https://github.com/ghostty-org/ghostty.git ~/projects/ghostty

# Build the xcframework (takes ~2-3 minutes)
cd ~/projects/ghostty
zig build -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=native

# Copy into the SlothyTerminal project root
cp -R macos/GhosttyKit.xcframework /path/to/slothy-terminal/
```

> **Note:** If the build fails with a Metal Toolchain error, install it first:
> ```bash
> xcodebuild -downloadComponent MetalToolchain
> ```

You only need to rebuild the xcframework when:
- You update the Ghostty source (`git pull` in the ghostty repo)
- You do a fresh clone of SlothyTerminal

#### 2. Open and run

```bash
open SlothyTerminal.xcodeproj
```

Press `Cmd+R` in Xcode to build and run.

#### CLI build and test

```bash
# Xcode build
xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build

# SwiftPM tests (does not require the xcframework)
swift test
```

## Project Structure

```
SlothyTerminal/
├── App/
│   ├── SlothyTerminalApp.swift    # App entry point and menu commands
│   ├── AppState.swift             # Global state management
│   └── AppDelegate.swift          # macOS app delegate
├── Views/
│   ├── MainView.swift             # Main window layout
│   ├── TabBarView.swift           # Tab bar with agent indicators
│   ├── TerminalView.swift         # Libghostty SwiftUI bridge
│   ├── TerminalContainerView.swift# Terminal display container
│   ├── SidebarView.swift          # Session statistics sidebar
│   ├── SettingsView.swift         # Settings window
│   ├── AboutView.swift            # About window
│   ├── FolderSelectorModal.swift  # Folder browser modal
│   └── TaskQueue/                 # Task queue UI (panel, composer, detail, row)
├── Models/
│   ├── Tab.swift                  # Tab model for chat/cli modes
│   ├── AgentType.swift            # Agent type enum (Terminal/Claude/OpenCode)
│   ├── UsageStats.swift           # Session statistics tracking
│   └── AppConfig.swift            # Configuration model
├── Chat/
│   ├── Engine/                    # Chat state machine and commands
│   ├── Transport/                 # Provider transports (Claude/OpenCode)
│   ├── OpenCode/                  # OpenCode parser/mapper/transport
│   ├── Storage/                   # Session snapshot persistence
│   ├── Parser/                    # Stream event parser types
│   ├── Models/                    # Chat/domain models
│   └── Views/                     # Chat UI, markdown, tool rendering
├── TaskQueue/
│   ├── Models/QueuedTask.swift    # Task model, status, priority, exit reasons
│   ├── Orchestrator/              # Task scheduling, preflight, timeout, retry
│   ├── Runner/                    # Claude/OpenCode runners, risky tool detection, log collector
│   ├── State/TaskQueueState.swift # @Observable queue state and mutations
│   └── Storage/                   # Queue snapshot persistence
├── Agents/
│   ├── AIAgent.swift              # Agent protocol and factory
│   ├── ClaudeAgent.swift          # Claude CLI integration
│   ├── OpenCodeAgent.swift        # OpenCode CLI integration
│   └── TerminalAgent.swift        # Plain terminal agent
├── Services/
│   ├── ConfigManager.swift        # Configuration persistence
│   ├── RecentFoldersManager.swift # Recent folders tracking
│   ├── StatsParser.swift          # Output parsing for stats
│   ├── UpdateManager.swift        # Sparkle update manager
│   ├── DirectoryTreeManager.swift # Directory tree scanning
│   ├── ExternalAppManager.swift   # External app integration
│   └── BuildConfig.swift          # Build environment config
├── Terminal/
│   ├── GhosttyApp.swift           # Libghostty app singleton and callbacks
│   └── GhosttySurfaceView.swift   # NSView subclass for terminal surfaces
└── Resources/
    ├── Config.debug.json          # Debug build configuration
    └── Config.release.json        # Release build configuration
```

## Release Process

Ensure `GhosttyKit.xcframework` is present in the project root, then:

```bash
./scripts/build-release.sh 2026.2.6
```

This archives, notarizes, creates a DMG, and signs for Sparkle updates. See [RELEASE.md](docs/RELEASE.md) for full step-by-step instructions.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-feature`)
3. Commit your changes (`git commit -m 'Add new feature'`)
4. Push to the branch (`git push origin feature/new-feature`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

**Maxim Gorbatyuk**
- GitHub: [@maximgorbatyuk](https://github.com/maximgorbatyuk)

## Acknowledgments

- [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto - GPU-accelerated terminal rendering via libghostty
- [Sparkle](https://github.com/sparkle-project/Sparkle) for the update framework
