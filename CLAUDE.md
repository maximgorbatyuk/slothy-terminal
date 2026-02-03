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
User Action → AppState.createTab() → Tab (with AIAgent)
                                        ↓
                                   PTYController.spawn() via forkpty()
                                        ↓
                              Terminal output → StatsParser → UsageStats
                                        ↓
                              TerminalView renders via SwiftTerm
```

### Key Components

- **AppState** (`App/AppState.swift`) - @Observable global state: tabs, active tab, sidebar, modals
- **Tab** (`Models/Tab.swift`) - Session model holding PTYController, UsageStats, and AIAgent
- **PTYController** (`Terminal/PTYController.swift`) - PTY management via POSIX forkpty(), reads output in background Task
- **AIAgent protocol** (`Agents/AIAgent.swift`) - Defines agent interface; implementations: ClaudeAgent, OpenCodeAgent, TerminalAgent
- **AgentFactory** - Creates appropriate agent instance based on AgentType enum
- **ConfigManager** (`Services/ConfigManager.swift`) - Singleton for persisting config to `~/Library/Application Support/SlothyTerminal/config.json`

### Adding a New Agent

1. Create struct conforming to `AIAgent` protocol in `Agents/`
2. Implement: `command`, `defaultArgs`, `environmentVariables`, `contextWindowLimit`, `parseStats()`, `isAvailable()`
3. Add case to `AgentType` enum
4. Update `AgentFactory.createAgent()`

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

## Dependencies

- **SwiftTerm** (1.5.1) - Terminal emulation and PTY handling
- **Sparkle** (2.8.1) - Automatic updates framework

## Known Issues (from findings.md)

Critical items to be aware of:
- `BuildConfig` uses `fatalError()` on missing config files - should degrade gracefully
- Force unwraps in `ConfigManager` can crash in edge cases
- `PTYController` uses `nonisolated(unsafe)` for outputContinuation, bypassing concurrency safety
- No test coverage exists for critical components
