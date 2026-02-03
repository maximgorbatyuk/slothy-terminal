# Changelog

All notable changes to SlothyTerminal will be documented in this file.

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

