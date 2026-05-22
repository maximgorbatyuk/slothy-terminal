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
- a built-in file editor with tree-sitter syntax highlighting (Swift, Markdown)
- workspace-based tab organization

Use Claude CLI, OpenCode, or plain terminal sessions in a clean tabbed interface with workspaces, saved prompts, an integrated file editor, and session statistics.

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

### File Editor
- Built-in `.editor` tab mode (no PTY, no agent — pure SwiftUI on top of [STTextView](https://github.com/krzyzanowskim/STTextView))
- Tree-sitter syntax highlighting with bundled Swift and Markdown grammars; other file types open as plain text on a theme-appropriate canvas
- Per-file-type theme — code on a dark canvas, prose (`.md`, `.markdown`, `.txt`) on a light canvas — independent of the system appearance
- Double-click a file in the Files sidebar to open it; existing editor tabs are focused instead of duplicated (symlink-resolved canonical URLs)
- Dirty-state indicator in the tab label (`● filename.swift`) and a Save / Don't Save / Cancel sheet on close
- Save (`Cmd+S`), Save As (`Cmd+Shift+S`), and Revert to Saved via the File menu
- Save-confirmation toast on every successful write
- Safety guards: 10 MB size cap, NUL-byte binary sniff, atomic write, symlink-follow on save, fallback decode through UTF-8 → CP1252 → MacRoman → ISO Latin-1
- Configurable editor font family and size from Settings → Appearance

### Saved Prompts
- Save and reuse prompts for AI agent sessions
- Inject saved prompts into active terminal sessions from the sidebar
- Prompt management in settings

### Directory Tree Browser
- Collapsible file tree showing project structure
- Displays files and folders with native system icons
- Shows hidden files (.github, .claude, .gitignore, etc.)
- Sorted display: folders first, then files (alphabetically)
- Double-click a file to open it in the built-in editor (accent-color hover state highlights the focused row)
- Right-click context menu:
  - Copy Relative Path
  - Copy Filename
  - Copy Full Path
- Lazy-loads subdirectories for performance

### Open in External Apps
- Quick-access dropdown to open the working directory in installed editors and chat apps. Detection is by bundle identifier — the menu shows whatever is actually installed on the machine.

![](/docs/assets/open_in.png)

### Settings
- **General** - Default agent, default tab mode, sidebar preferences, recent folders
- **Agents** - Custom paths for Claude and OpenCode CLIs
- **Appearance** - Terminal font family and size, editor font family and size, agent accent colors
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

### Editor
| Action | Shortcut |
|--------|----------|
| Save | `Cmd+S` |
| Save As… | `Cmd+Shift+S` |
| Revert to Saved | — (File menu) |

The editor File menu items are always rendered so `Cmd+S` stays claimed app-wide — otherwise it would fall through to the focused terminal and send `^S` (XOFF), freezing the foreground process.

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
- Editor font family and size
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
- [STTextView](https://github.com/krzyzanowskim/STTextView) - AppKit text view backing the built-in file editor (SPM)
- [SwiftTreeSitter](https://github.com/ChimeHQ/SwiftTreeSitter) + bundled `TreeSitterSwift` / `TreeSitterMarkdown` grammars - syntax highlighting for the editor (SPM)

The STTextView and tree-sitter packages are linked only into the Xcode app target; the SPM test target excludes them. See [`docs/architecture.md`](docs/architecture.md) and [`docs/testing.md`](docs/testing.md).

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

Source lives under [`SlothyTerminal/`](SlothyTerminal/). Each subdirectory has a single responsibility:

| Path | Purpose |
|---|---|
| [`App/`](SlothyTerminal/App) | `@main` entry point, `AppDelegate`, global `AppState`. |
| [`Agents/`](SlothyTerminal/Agents) | `AIAgent` protocol and per-agent CLI integration (Claude, OpenCode, plain terminal). |
| [`Models/`](SlothyTerminal/Models) | Plain value types — `Tab`, `Workspace`, `AppConfig`, `SavedPrompt`, etc. |
| [`Services/`](SlothyTerminal/Services) | Long-running services and stateless utilities — config, git, usage, logging, scanners. |
| [`Injection/`](SlothyTerminal/Injection) | Per-tab FIFO queue and live-surface registry for programmatic terminal input. |
| [`Terminal/`](SlothyTerminal/Terminal) | libghostty C-ABI boundary (`GhosttyApp`, `GhosttySurfaceView`). Xcode-only. |
| [`Views/`](SlothyTerminal/Views) | All SwiftUI views — main window, tab bar, sidebars, settings, git client, dialogs. |
| [`Views/Editor/`](SlothyTerminal/Views/Editor) | File editor tab — STTextView host, tree-sitter highlighting plugin, theme palette, File menu hooks. Xcode-only. |
| [`Resources/`](SlothyTerminal/Resources) | Build-config JSON, bundled fonts, third-party licences. |

For module responsibilities and the SPM-vs-Xcode build split, see [`docs/architecture.md`](docs/architecture.md).

## Documentation

- [`AGENTS.md`](AGENTS.md) — orientation, hard rules, build commands, Swift style guidance for AI assistants and human contributors ([`CLAUDE.md`](CLAUDE.md) re-exports this)
- [`docs/architecture.md`](docs/architecture.md) — runtime boundary, modules, deployment surface
- [`docs/domain.md`](docs/domain.md) — Workspace / Tab / AgentType / Injection lifecycle and invariants
- [`docs/authentication.md`](docs/authentication.md) — Keychain, notarization, Sparkle EdDSA
- [`docs/interactions.md`](docs/interactions.md) — libghostty boundary, spawned subprocesses, outbound HTTP
- [`docs/testing.md`](docs/testing.md) — what `swift test` covers, what it can't, CI gates
- [`docs/gotchas.md`](docs/gotchas.md) — known traps and unsafe shortcuts
- [`docs/release.md`](docs/release.md) — full step-by-step release instructions
- [`docs/ui-guideline.md`](docs/ui-guideline.md) — design guidelines
- [`docs/roadmap.md`](docs/roadmap.md) — project roadmap
- [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) — unresolved product behaviour

## Release Process

The release pipeline is driven by `scripts/release.sh`. It is **idempotent on `VERSION`** — a failed run can be re-invoked with the same version and it will resume rather than re-bump the build number.

Prerequisites:

- `GhosttyKit.xcframework` present in the project root
- `.env` with Apple notarization credentials
- `sparkle-tools/bin/sign_update` installed
- `gh` CLI authenticated

Before running, hand-edit two files:

1. `CHANGELOG.md` — add a `[VERSION]` entry.
2. `appcast.xml` — add an `<item>` with `BUILD_NUMBER`, `SIGNATURE_HERE`, and `FILE_SIZE_IN_BYTES` placeholders. The script substitutes them after building.

Then:

```bash
./scripts/release.sh 2026.2.6
# or, to auto-bump the patch segment of the current MARKETING_VERSION:
./scripts/release.sh
```

`release.sh` bumps `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in `project.pbxproj`, invokes `build-release.sh` (archive → notarize → DMG → staple), signs the DMG with Sparkle, fills the appcast placeholders, commits the release files, pushes, merges to `main`, and creates a GitHub Release with the DMG attached.

See [`docs/release.md`](docs/release.md) for the full step-by-step description, idempotency rules, and troubleshooting.

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
