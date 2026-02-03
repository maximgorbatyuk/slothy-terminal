# Codex Findings - SlothyTerminal

This document lists potential issues, bugs, and security findings discovered during a static review of the repository.

## High

1. **[CDX-001] Custom agent path setting is ignored**
   - **Where:** `SlothyTerminal/Views/SettingsView.swift`, `SlothyTerminal/Models/AppConfig.swift`, `SlothyTerminal/Agents/ClaudeAgent.swift`, `SlothyTerminal/Agents/OpenCodeAgent.swift`
   - **What:** The Settings UI writes `config.claudePath` / `config.opencodePath`, but the agents only consult environment variables (`CLAUDE_PATH`, `OPENCODE_PATH`) and never read the config. The helper `ConfigManager.customPath(for:)` is also unused.
   - **Impact:** Users cannot actually override agent paths from the Settings UI; the app reports “Not Found” even when a custom path was selected.
   - **Fix:** Feed `ConfigManager.shared.customPath(for:)` into `Agent.command` (or into the launch environment) and update `isAvailable()` to check the configured path first.

2. **[CDX-002] Global working directory is mutated when launching terminals**
   - **Where:** `SlothyTerminal/Views/TerminalView.swift`
   - **What:** `FileManager.default.changeCurrentDirectoryPath(workingDirectory.path)` is called on the main app process before launching the shell.
   - **Impact:** The app’s current working directory becomes whatever tab was started last. This can cause cross‑tab interference, unexpected relative-path behavior in other code, and race conditions when multiple tabs launch concurrently.
   - **Fix:** Avoid changing the process CWD. If the terminal library can’t set a working directory directly, spawn a wrapper command (`/usr/bin/env`, `cd`, etc.) or use APIs that accept a working directory for the child process.

3. **[CDX-003] Agent availability checks miss PATH-installed binaries**
   - **Where:** `SlothyTerminal/Agents/ClaudeAgent.swift`, `SlothyTerminal/Agents/OpenCodeAgent.swift`
   - **What:** `isAvailable()` only checks environment overrides and a fixed list of common paths; it does not search the user’s PATH.
   - **Impact:** If users installed `claude`/`opencode` in a custom PATH location, the app incorrectly reports the agent as missing and blocks session creation.
   - **Fix:** Resolve binaries via PATH (e.g., `which` or manual PATH search), or reuse the same resolution logic as the shell used for execution.

4. **[CDX-004] Shortcut customization is not wired to the app commands**
   - **Where:** `SlothyTerminal/Views/SettingsView.swift`, `SlothyTerminal/Models/AppConfig.swift`, `SlothyTerminal/App/SlothyTerminalApp.swift`
   - **What:** The settings UI stores custom shortcuts in `config.shortcuts`, but command definitions in `SlothyTerminalApp` use static `keyboardShortcut` modifiers only.
   - **Impact:** The Shortcuts tab is effectively read-only; changes never affect actual shortcuts.
   - **Fix:** Use `config.shortcuts` to configure `KeyboardShortcut` or hook a shortcut manager that reads from config.

## Medium

5. **[CDX-005] Usage stats ignore `totalTokens` and `contextWindowUsed`**
   - **Where:** `SlothyTerminal/Services/StatsParser.swift`, `SlothyTerminal/Models/UsageStats.swift`
   - **What:** `StatsParser` sets `UsageUpdate.totalTokens` and `contextWindowUsed`, but `UsageStats.applyUpdate` never reads them. Only `tokensIn`/`tokensOut` and `contextWindowLimit` are applied.
   - **Impact:** If the CLI outputs only total tokens or context usage, the UI can stay at zero and show incorrect percentages.
   - **Fix:** Add fields to `UsageStats` for `contextWindowUsed` (or update tokens from total), and apply `totalTokens` when `tokensIn/out` are missing.

6. **[CDX-006] Custom accent colors are never used**
   - **Where:** `SlothyTerminal/Services/ConfigManager.swift`, `SlothyTerminal/Views/*` (e.g., `TabBarView.swift`, `MainView.swift`)
   - **What:** `ConfigManager.accentColor(for:)` exists, and Settings persist custom colors, but UI components use `agentType.accentColor` directly.
   - **Impact:** Changing accent colors in Settings has no visible effect.
   - **Fix:** Replace direct uses of `agentType.accentColor` with `ConfigManager.shared.accentColor(for:)` in UI views.

7. **[CDX-007] Agent environment variables are never applied**
   - **Where:** `SlothyTerminal/Models/Tab.swift`, `SlothyTerminal/Views/TerminalView.swift`
   - **What:** `Tab.environment` returns `agent.environmentVariables`, but terminal launch ignores it and builds env solely from `ProcessInfo.processInfo.environment`.
   - **Impact:** Any agent-specific env (current or future) won’t be passed to the CLI as intended.
   - **Fix:** Merge `tab.environment` into the environment passed to `startProcess`.

8. **[CDX-008] Window move observer is not retained**
   - **Where:** `SlothyTerminal/App/AppDelegate.swift`
   - **What:** The observer for `NSWindow.didMoveNotification` is created but its token is not stored, so it is deallocated immediately.
   - **Impact:** Window position changes are not persisted; only resize events are saved.
   - **Fix:** Store the returned observer token (and remove it on termination if desired), similar to `windowObserver`.

9. **[CDX-009] Auto-run command string is not safely escaped**
   - **Where:** `SlothyTerminal/Views/TerminalView.swift`
   - **What:** `autoRunCommand` only quotes arguments that contain spaces and does not escape quotes or shell metacharacters. The command path itself is not quoted.
   - **Impact:** Paths with spaces can fail to run; if environment/config values contain shell metacharacters, they could be interpreted by the shell.
   - **Fix:** Use a robust shell-escaping routine or avoid a shell-based launch path by executing the CLI directly.

## Low

10. **[CDX-010] Recent folder limit ignores user setting**
    - **Where:** `SlothyTerminal/Services/RecentFoldersManager.swift`, `SlothyTerminal/Views/SettingsView.swift`
    - **What:** The manager uses a hard-coded `maxRecentFolders = 10`, while Settings allow configuring `config.maxRecentFolders`.
    - **Impact:** The Settings option has no effect.
    - **Fix:** Read the max count from `ConfigManager.shared.config.maxRecentFolders`.

11. **[CDX-011] Invalid recent folders are not cleaned up in persistent storage**
    - **Where:** `SlothyTerminal/Services/RecentFoldersManager.swift`
    - **What:** `loadRecentFolders()` filters non-existent paths in memory but does not write the cleaned list back to `UserDefaults`.
    - **Impact:** `UserDefaults` can grow stale and re-filter on every launch.
    - **Fix:** Call `saveRecentFolders()` after filtering.

12. **[CDX-012] Startup config load uses hard crash paths**
    - **Where:** `SlothyTerminal/Services/BuildConfig.swift`
    - **What:** Missing or malformed config files trigger `fatalError` during app startup.
    - **Impact:** A missing bundle resource (or corrupted JSON) hard-crashes the app with no recovery.
    - **Fix:** Fall back to safe defaults and surface a warning rather than terminating.

13. **[CDX-013] Force unwrap of Application Support directory**
    - **Where:** `SlothyTerminal/Services/ConfigManager.swift`
    - **What:** `FileManager.default.urls(...).first!` assumes a value always exists.
    - **Impact:** In rare edge cases (or sandboxing misconfiguration), this can crash.
    - **Fix:** Use `guard let` and fall back to `FileManager.default.homeDirectoryForCurrentUser` or a safer default.
