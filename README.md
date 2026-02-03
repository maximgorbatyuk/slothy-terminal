# SlothyTerminal

A native macOS terminal application designed for AI coding assistants with a tabbed interface and session tracking.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Overview

SlothyTerminal provides a unified terminal environment for working with AI coding agents. Run Claude CLI, OpenCode, or plain terminal sessions in a clean tabbed interface with real-time session statistics.

## Features

### Multi-Agent Support
- **Terminal** - Plain shell sessions
- **Claude** - Claude CLI integration for AI-assisted coding
- **OpenCode** - OpenCode CLI integration

### Tabbed Interface
- Multiple concurrent sessions
- Quick tab switching with `Cmd+1-9`
- Visual agent indicators with accent colors
- Close tabs with `Cmd+W`

### Session Statistics Sidebar
- Current working directory display
- Session duration timer
- Command counter
- Configurable sidebar position (left/right)

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

### Settings
- **General** - Default agent, sidebar preferences, recent folders
- **Agents** - Custom paths for Claude and OpenCode CLIs
- **Appearance** - Terminal font family and size, agent accent colors
- **Shortcuts** - View keyboard shortcuts

### Additional Features
- Recent folders quick access
- Automatic updates via Sparkle framework
- Dark mode optimized
- Native macOS integration

## Screenshot

```
┌─────────────────────────────────────────────────────────────────────────┐
│ ● ● ●                        SlothyTerminal                            │
├─────────────────────────────────────────────────────────────────────────┤
│ [C] ~/projects/app  │ [O] ~/api  │ [T] ~/scripts  │        [+]         │
├───────────────────────────────────────────────────┬─────────────────────┤
│                                                   │  Working Directory  │
│                                                   │  ~/projects/app     │
│  claude ❯ help me refactor the auth module       │                     │
│                                                   │  [Open in...     v] │
│  I'll analyze the authentication code...         │                     │
│                                                   │  📁 Files           │
│  Reading: src/auth/index.ts                      │  ├── .github/       │
│  Reading: src/auth/middleware.ts                 │  ├── src/           │
│                                                   │  ├── tests/         │
│  claude ❯ █                                      │  ├── package.json   │
│                                                   │  └── README.md      │
│                                                   │                     │
│                                                   │  SESSION INFO       │
│                                                   │  Duration  12m 34s  │
│                                                   │  Commands       8   │
├───────────────────────────────────────────────────┴─────────────────────┤
│                                                            v2026.2.2    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Installation

### Download

Download the latest DMG from [GitHub Releases](https://github.com/maximgorbatyuk/slothy-terminal/releases).

1. Open the DMG file
2. Drag SlothyTerminal to Applications
3. Launch from Applications folder

### Requirements

- macOS 13.0 or later
- [Claude CLI](https://claude.ai/code) (optional)
- [OpenCode](https://opencode.ai) (optional)

## Keyboard Shortcuts

### Tabs
| Action | Shortcut |
|--------|----------|
| New Terminal Tab | `Cmd+T` |
| New Claude Tab | `Cmd+Shift+T` |
| New OpenCode Tab | `Cmd+Option+T` |
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

### Appearance Settings
- Terminal font family (monospaced fonts)
- Terminal font size (10-24pt)
- Custom accent colors for agents

## Building from Source

### Prerequisites

- Xcode 15.0+
- macOS 13.0+

### Dependencies

Add via Swift Package Manager:
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) - Terminal emulation
- [Sparkle](https://github.com/sparkle-project/Sparkle) - Auto-updates

### Build

```bash
git clone https://github.com/maximgorbatyuk/slothy-terminal.git
cd slothy-terminal
open SlothyTerminal.xcodeproj
```

Press `Cmd+R` in Xcode to build and run.

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
│   ├── TerminalView.swift         # SwiftTerm wrapper
│   ├── TerminalContainerView.swift# Terminal display container
│   ├── SidebarView.swift          # Session statistics sidebar
│   ├── SettingsView.swift         # Settings window (4 tabs)
│   ├── AboutView.swift            # About window
│   └── FolderSelectorModal.swift  # Folder browser modal
├── Models/
│   ├── Tab.swift                  # Tab model with PTY controller
│   ├── AgentType.swift            # Agent type enum (Terminal/Claude/OpenCode)
│   ├── UsageStats.swift           # Session statistics tracking
│   └── AppConfig.swift            # Configuration model
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
│   └── PTYController.swift        # PTY/process management
└── Resources/
    ├── Config.debug.json          # Debug build configuration
    └── Config.release.json        # Release build configuration
```

## Release Process

See [RELEASE.md](RELEASE.md) for step-by-step release instructions.

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

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza
- [Sparkle](https://github.com/sparkle-project/Sparkle) for the update framework
