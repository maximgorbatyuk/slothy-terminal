# SlothyTerminal

A native macOS terminal application designed for AI coding assistants with a tabbed interface, workspace management, and session tracking.

Privacy-first by design. See the [Privacy Policy](PRIVACY.md).

Known limitations and unresolved behavior are tracked in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

![macOS](https://img.shields.io/badge/macOS-15.0+-blue)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1+-8A2BE2)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Overview

SlothyTerminal provides a unified macOS workspace for AI coding agents with:
- Claude CLI and OpenCode CLI terminal tabs
- plain shell terminal tabs
- a built-in Git repository browser
- workspace-based tab organization

Use Claude CLI, OpenCode, or plain terminal sessions in a clean tabbed interface with workspaces, saved prompts, and session statistics.

## Features

### Multi-Agent Support
- **Terminal** - Plain shell sessions powered by libghostty (Metal-accelerated)
- **Claude** - Claude CLI/TUI terminal tabs
- **OpenCode** - OpenCode CLI/TUI terminal tabs
- **Git Client** - Built-in Git repository browser

![](/docs/assets/main_window.png)

### Tabbed Interface
- Multiple concurrent sessions
- Quick tab switching with `Cmd+1-9`
- Visual agent indicators with accent colors
- Close tabs with `Cmd+W`
- Tab names: `Claude | cli`, `Opencode | cli`, `Terminal | cli`, `Git client`
- Plain terminal tabs show the last submitted command in the tab label

![](/docs/assets/open_new_tab.png)

### Workspaces
- Named project directory containers for organizing tabs
- Switch between workspaces to focus on different projects
- Drag-and-drop workspace reordering in the sidebar
- Empty workspaces retarget to new directories automatically
- Split view support for side-by-side terminal sessions

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

### Git Client
- Built-in Git repository browser (no agent or PTY — pure SwiftUI)
- Repository overview with summary stats and author activity
- Revision graph with lane-based commit visualization
- Activity heatmap grid
- Commit composer with file picker, diff viewer, and commit message editor
- Working tree changes display

### Saved Prompts
- Save and reuse prompts for AI agent sessions
- Inject saved prompts into active terminal sessions from the sidebar
- Prompt management in settings

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
- **Appearance** - Terminal font family and size, agent accent colors
- **Shortcuts** - View keyboard shortcuts
- **Prompts** - Manage saved prompts
- **Licenses** - Third-party license information

### Additional Features
- Smart Claude CLI path resolution preferring native Mach-O binaries over Node.js wrappers
- Recent folders quick access
- Automatic updates via Sparkle framework
- Compact native title bar with contextual window title
- Terminal interaction mode (Host Selection for text selection, App Mouse for TUI forwarding)
- Terminal input injection subsystem for programmatic command delivery
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
- Apple Silicon Mac (M1 or later)
- [Claude CLI](https://claude.ai/code) (optional)
- [OpenCode](https://opencode.ai) (optional)

## Keyboard Shortcuts

### Tabs
| Action | Shortcut |
|--------|----------|
| New Session | `Cmd+T` |
| New Session in Split View | `Cmd+Option+T` |
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

# SwiftPM core validation (does not require the xcframework)
swift build
swift test
```

The `SwiftPM` GitHub Actions workflow validates this SwiftPM core only. It does not build Ghostty-dependent or other app-only code from the Xcode target.

If new code is intended to be part of the SwiftPM-covered core and is SwiftPM-compatible, add it to `Package.swift` so it stays covered by `swift build`, `swift test`, and CI. If it depends on the Ghostty/AppKit terminal runtime, or is otherwise app-only, keep it Xcode-only. Concrete Xcode-only examples include `Terminal/GhosttyApp.swift`, `Terminal/GhosttySurfaceView.swift`, `Views/`, and app-only integrations such as Sparkle-backed `Services/UpdateManager.swift`. The `SlothyTerminalLib` target uses an explicit `sources:` list, so SwiftPM-covered non-UI files must be added there manually.

## Project Structure

```
SlothyTerminal/
├── App/
│   ├── SlothyTerminalApp.swift    # App entry point and menu commands
│   ├── AppState.swift             # Global state management
│   └── AppDelegate.swift          # macOS app delegate
├── Agents/
│   ├── AIAgent.swift              # Agent protocol and factory
│   ├── ClaudeAgent.swift          # Claude CLI integration
│   ├── OpenCodeAgent.swift        # OpenCode CLI integration
│   └── TerminalAgent.swift        # Plain terminal agent
├── Injection/
│   ├── Models/                    # InjectionPayload, InjectionRequest, InjectionTarget
│   ├── Orchestrator/              # Per-tab FIFO injection queues
│   └── Registry/                  # TerminalSurfaceRegistry for live surfaces
├── Models/
│   ├── Tab.swift                  # Tab model (terminal/git modes)
│   ├── AgentType.swift            # Agent type enum (Terminal/Claude/OpenCode)
│   ├── Workspace.swift            # Workspace model for tab grouping
│   ├── GitStats.swift             # Git statistics and graph models
│   ├── GitTab.swift               # Git client sub-tab enum
│   ├── SavedPrompt.swift          # Saved prompt model
│   ├── LaunchType.swift           # Session launch type enum
│   └── AppConfig.swift            # Configuration model
├── Services/
│   ├── ConfigManager.swift        # Configuration persistence
│   ├── GitService.swift           # Async git operations
│   ├── GitStatsService.swift      # Repository statistics
│   ├── GitProcessRunner.swift     # Git command runner (deadlock-safe)
│   ├── GitWorkingTreeService.swift# Working tree change detection
│   ├── GraphLaneCalculator.swift  # Revision graph lane assignment
│   ├── OpenCodeCLIService.swift   # OpenCode CLI wrapper
│   ├── ANSIStripper.swift         # ANSI escape sequence removal
│   ├── DirectoryTreeManager.swift # Directory tree scanning
│   ├── ExternalAppManager.swift   # External app integration
│   ├── RecentFoldersManager.swift # Recent folders tracking
│   ├── UpdateManager.swift        # Sparkle update manager
│   └── BuildConfig.swift          # Build environment config
├── Terminal/
│   ├── GhosttyApp.swift           # Libghostty app singleton and callbacks
│   └── GhosttySurfaceView.swift   # NSView subclass for terminal surfaces
├── Views/
│   ├── MainView.swift             # Main window layout
│   ├── TabBarView.swift           # Tab bar with agent indicators
│   ├── TerminalView.swift         # Libghostty SwiftUI bridge
│   ├── TerminalContainerView.swift# Terminal display container
│   ├── SidebarView.swift          # Session statistics sidebar
│   ├── WorkspacesSidebarView.swift# Workspace management sidebar
│   ├── PromptsSidebarView.swift   # Saved prompts sidebar
│   ├── GitClientView.swift        # Git client container
│   ├── MakeCommitView.swift       # Commit composer
│   ├── RevisionGraphView.swift    # Commit history graph
│   ├── GitChangesView.swift       # Working tree changes
│   ├── StartupPageView.swift      # New session startup page
│   ├── SettingsView.swift         # Settings window
│   ├── AboutView.swift            # About window
│   └── FolderSelectorModal.swift  # Folder browser modal
└── Resources/
    ├── Config.debug.json          # Debug build configuration
    └── Config.release.json        # Release build configuration
```

## Documentation

- [Release Process](docs/RELEASE.md) - Full step-by-step release instructions
- [UI Guidelines](docs/ui-guideline.md) - Design guidelines
- [Roadmap](docs/roadmap.md) - Project roadmap

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
