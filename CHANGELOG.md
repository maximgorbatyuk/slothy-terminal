# Changelog

All notable changes to SlothyTerminal will be documented in this file.

## [2026.3.6] - 2026-04-29

### Fixed
- **Release tags now point to the correct commit.** `scripts/release.sh` previously invoked `gh release create $TAG` *before* pushing `develop` and merging into `main`. With no `--target` flag, `gh release create` asks GitHub to create the tag against the latest state of the default branch on the server — and at that moment `main` still pointed at the *previous* release's `chore: release X-1` commit. Net effect: every tag from `v2026.3.1` through `v2026.3.5` is offset, pointing at the bump commit for the previous version. Sparkle and the GitHub Releases UI were unaffected (the DMG is uploaded explicitly and read via `appcast.xml`), but `git checkout v2026.3.5` got you 2026.3.4 source. Fix: reordered the script so push/merge to `main` happens *before* the GitHub release is created, and added `--target main` to `gh release create` so the tag is bound explicitly to the freshly-pushed `main` HEAD. (`scripts/release.sh:270-326`)

### Notes
- This fix is forward-only: tags `v2026.3.1` through `v2026.3.5` remain bound to the wrong commits in the GitHub repository. They can be retagged manually if needed (`git tag -f vX <sha> && git push origin :refs/tags/vX && git push origin vX`), but doing so isn't required for Sparkle auto-update — only for source-checkout consumers.

## [2026.3.5] - 2026-04-29

### Changed
- **Cursor authentication is now auto-detected from Cursor.app.** SlothyTerminal reads the current session JWT directly from Cursor's own SQLite state database at `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` (row `cursorAuth/accessToken`), so no manual setup is required when Cursor.app is installed and the user is signed in. The DB is opened read-only with `SQLITE_OPEN_NOMUTEX` so it's safe alongside a running Cursor instance; brief exclusive locks during Cursor writes are covered by the metric-cache fallback added in 2026.3.4. JWT rotation is picked up automatically — every fetch reads the latest token from disk. (`SlothyTerminal/Services/CursorUsageProvider.swift`)
- **`UsageService.resolveCursorAuth()` priority order**: 1) auto-detect via `CursorUsageProvider.canReadStateDB()` (`.cliOAuth`, label "Cursor app"), 2) fall back to the existing manually-pasted JWT in our Keychain (`.apiKey`, label "Session token"). `fetchCursorUsage(source:)` now dispatches by `source.kind`; the SQLite read happens off the main actor via `Task.detached`. Existing manual-paste tokens continue to work unchanged when Cursor.app is unavailable. (`SlothyTerminal/Services/UsageService.swift`)
- **`CursorUsageProvider.fetchUsage` accepts `sourceKind` and `sourceLabel`** so the popover badge reflects whether the JWT came from auto-detect ("Cursor app") or a manual paste ("Session token"). `parseUsageResponse` and `failureSnapshot` propagate the same fields. (`SlothyTerminal/Services/CursorUsageProvider.swift`)
- **Settings → Usage → Cursor section reframed.** The auto-detect status is now the headline (one of three states: auto-detected from Cursor.app / using manually-pasted token / not connected) with a contextual subtitle. The JWT paste field is collapsed inside a `DisclosureGroup` labelled "Manual override" with copy explicitly directing users there only when Cursor.app isn't installed or auto-detect fails. (`SlothyTerminal/Views/SettingsView.swift`)

### Notes
- `import SQLite3` resolves to the system-bundled libsqlite3 on macOS — no Swift Package Manager dependency, no `Package.swift` change required.

## [2026.3.4] - 2026-04-29

### Added
- **Cursor usage tracking in the menubar.** A new "Usage" section in Settings accepts a Cursor session JWT (the second half of the `WorkosCursorSessionToken` cookie set by cursor.com). The token is stored in the macOS Keychain via `UsageKeychainStore`, and the menubar usage strip polls `https://www.cursor.com/api/usage` for monthly request counts and reset dates. JWT decoding is pure Foundation — the `sub` claim supplies the user ID required by the endpoint and is validated against an RFC 6265 cookie-octet character set before being placed in the `Cookie` header verbatim. (`SlothyTerminal/Services/CursorUsageProvider.swift`, `SlothyTerminal/Services/UsageService.swift`)
- **`SettingsSection.usage`** — new Settings tab housing the master usage-tracking toggle and per-provider configuration. Currently surfaces the Cursor JWT paste flow with Save / Clear actions and a saved-state indicator. (`SlothyTerminal/Models/SettingsSection.swift`, `SlothyTerminal/Views/SettingsView.swift`)
- **`UsageProvider.cursor`** case + `statusBarProviders` entry, with `displayName` "Cursor" and SF Symbol `cursorarrow.rays`. (`SlothyTerminal/Models/UsageModels.swift`)

### Changed
- **Claude umbrella usage windows now prefix-merge across model-suffixed variants.** The Anthropic OAuth response is evolving to include keys like `seven_day_sonnet_4_5`, `seven_day_opus_4_1`, etc. `mergedClaudeWindow(_:baseKey:)` returns the API's exact `seven_day` / `five_hour` value when present (authoritative aggregate), and falls back to merging `baseKey_*` siblings (max utilization, earliest reset) when no exact key exists. New per-model variants surface in the popover automatically without code changes. (`SlothyTerminal/Services/UsageService.swift`)
- **Claude usage now survives transient API failures.** A new `UserDefaults`-backed metric cache stores `(utilization, resetsAt)` for the `five_hour` and `seven_day` windows. `parseClaudeOAuthUsageResponse` prefers a cached non-zero value over a fresh 0% when the reset boundary hasn't moved (idle-session API gap), and `fetchClaudeUsageViaOAuth` falls back to `cachedClaudeSnapshot` (with a "Cached (offline)" badge in the popover) on network errors and 5xx responses. 401 still clears the OAuth-token cache and surfaces `.tokenExpired` for explicit user renewal — unchanged. Cache entries auto-expire once their `resetsAt` elapses; writes without a reset boundary are refused so the cache can never pin a value indefinitely. `clearProvider(.claude)` and `clearAll()` wipe the metric cache alongside the OAuth-token cache. (`SlothyTerminal/Services/UsageService.swift`)
- **Status-bar usage strip hides both `.idle` and `.unavailable` providers** instead of just `.idle`. Keeps the menubar clean when a provider enum case exists but no auth source is configured (e.g., no Cursor JWT saved). (`SlothyTerminal/Views/StatusBarUsageView.swift`)

### Removed
- `formatISO8601ResetTime` helper in `UsageService` — superseded by the new `parseClaudeISO8601` + existing `formatResetDate` pipeline used by the merge/cache code.

### Security
- **Cookie-header injection guards.** `CursorUsageProvider.isHeaderSafe(_:)` validates JWTs and the decoded user-ID against `[A-Za-z0-9._-]` (RFC 6265 cookie-octet range) before placement in the `Cookie` header. This eliminates the need for percent-encoding — which would corrupt cookie values in transit — while preventing CR/LF/null-byte injection. (`SlothyTerminal/Services/CursorUsageProvider.swift`)
- **Proper URL query encoding.** Cursor user IDs are passed via `URLComponents` + `URLQueryItem` rather than string concatenation, so any characters outside the validated charset would be encoded correctly instead of silently corrupting the request URL.
- **Fail-loud Cursor response parsing.** `parseUsageResponse` returns a "Parse error" snapshot when the response is missing both `startOfMonth` and any model entries, surfacing schema breakage instead of silently presenting zero usage.

## [2026.3.3] - 2026-04-17

### Fixed
- **Agent tabs no longer freeze when the CLI exits.** Claude and OpenCode tabs previously spawned the CLI binary as the PTY's primary process; when the user exited the CLI (e.g. Ctrl+D in Claude), the PTY had no process left and the surface stopped responding to keystrokes. Agent tabs now launch under the default shell and the agent command is injected into that shell once the prompt is ready, so exiting the CLI returns the user to a usable shell prompt instead of a frozen view. (`SlothyTerminal/Views/TerminalContainerView.swift`)
- **Prompt-readiness detection replaces fixed-delay injection.** The auto-launch flow now waits for the injection registry to register the surface and then polls Ghostty's render-dirty flag until the terminal is quiet for 150ms (bounded to 3s), so slow shell startups (Oh-My-Zsh, powerlevel10k, corporate dotfiles) no longer race the injector. A Ctrl+U is sent before the agent command to discard anything the user may have typed into the prompt during the startup window.
- **Auto-launch is now one-shot per view lifetime.** A `didAutoLaunchAgent` guard prevents `.task` re-fires (triggered by tab reorder or workspace moves) from injecting the agent command a second time into an already-running agent.

### Added
- `AgentType.needsShellHost` — decouples "must run under a shell host" from `supportsInitialPrompt` (which still drives the prompt-picker in `FolderSelectorModal`). Currently true for `.claude` and `.opencode`.
- `ControlSignal.ctrlU` (ASCII 21) — used to clear any user preamble in the shell line editor before injecting the agent command.
- Startup status banner in agent tabs — a small "Starting <agent>…" overlay is shown while the flow waits for the shell prompt to settle.

### Changed
- **"Start New Session" modal renamed to "New tab"** (`SlothyTerminal/Views/StartupPageView.swift`). The split-view variant is now labelled "New tab in split view".

## [2026.3.2] - 2026-04-13

### Added
- **Prompt files viewer** — the Prompts sidebar now lists `.md` and `.txt` files discovered recursively under `<workspace>/docs/prompts/`, rendered below saved prompts under a "Files from docs/prompts" section. Double-clicking a file (or using the "Copy to clipboard" context-menu action) reads its contents and copies them to the system clipboard; a green status message confirms the copy. A "Reveal in Finder" context-menu action opens the file in Finder. Files refresh automatically on workspace switch and via a refresh button in the section header. (`SlothyTerminal/Models/PromptFile.swift`, `SlothyTerminal/Services/PromptFilesScanner.swift`, `SlothyTerminal/Views/PromptsSidebarView.swift`)
- `PromptFilesScanner` — async recursive file scanner with UTF-8 → Latin-1 decode fallback for reading file contents, filtered to `.md` / `.txt` case-insensitively.

### Changed
- **`scripts/release.sh` accepts `VERSION` as optional** — when omitted, the script auto-derives the next patch version by bumping the last dot-separated segment of `MARKETING_VERSION` (e.g. `2026.3.1 → 2026.3.2`). An explicit `VERSION` argument overrides the auto-derivation.
- **`scripts/release.sh` commits pending working-tree changes before releasing** — after preflight checks pass, any uncommitted or untracked files are staged (`git add -A`) and committed with the message `Commit before release VERSION`, so the subsequent release-bump commit stays focused on version metadata only.

### Tests
- Added `PromptFilesScannerTests` — 8 tests covering missing/empty folder, extension filtering, case-insensitive matching, recursion into subfolders, alphabetical sort order, and UTF-8 round-trip.

## [2026.3.1] - 2026-04-10

### Added
- **GhosttyKit update script** (`scripts/update-ghostty.sh`) — automates the full GhosttyKit.xcframework update workflow from within the SlothyTerminal repo: pulls latest Ghostty source, builds the xcframework, copies it into the project, and runs verification builds. Supports `--tag <version>` to pin to a specific Ghostty release and `--ghostty-dir <path>` for custom source locations.

## [2026.2.27] - 2026-04-09

### Changed
- **Workspaces pinned to top of sidebar** — the Workspaces panel is no longer a switchable sidebar tab. It is now always visible at the top of the sidebar, occupying up to half the sidebar height, with the remaining tabs (Explorer, Prompts, Automation) switching below it.

### Removed
- `.workspaces` case from `SidebarTab` enum — existing configs with the old value decode gracefully to `.explorer`.

## [2026.2.26] - 2026-04-05

### Fixed
- **Terminal font scaling on display changes and tab switches** — the font size no longer becomes incorrect when switching between displays with different DPI or when switching between tabs. Three root causes were identified and fixed by comparing with Ghostty upstream:
  - Removed wrapper-side size dedup cache that blocked necessary `ghostty_surface_set_size` re-sends (GhosttyKit deduplicates internally)
  - Changed `contentSize` to a computed property with `frame.size` fallback, preventing zero-size values from corrupting scale calculations
  - Tab activation now re-sends both content scale and size via a deferred refresh mechanism, instead of only re-sending size
  - Added zero-size guard to prevent hidden tabs from sending `NaN` scale factors to GhosttyKit

### Removed
- `GhosttySurfaceMetricsCache` — the wrapper-side dedup cache has been removed entirely. GhosttyKit handles deduplication internally.

## [2026.2.25] - 2026-04-03

### Fixed
- **Terminal font scaling on display changes (follow-up)** — the initial fix in 2026.2.24 did not fully resolve the issue. The deeper root causes: `ghostty_surface_set_content_scale` was skipped by a dedup cache when both screens had the same backing scale factor (e.g. both 2x Retina), and scale factors were read synchronously before the view's coordinate space had settled on the new display. Content scale is now sent unconditionally (matching Ghostty upstream), and the screen-change handler dispatches `viewDidChangeBackingProperties()` asynchronously so coordinate conversions reflect the new display.

## [2026.2.24] - 2026-04-02

### Fixed
- **Terminal font scaling on display changes** — switching between displays with different pixel densities (e.g. closing the laptop lid while connected to an external monitor, or detaching the monitor) no longer leaves the terminal font at the wrong size. The root cause was that `ghostty_surface_set_display_id` was never called, so GhosttyKit's Metal renderer did not know which display the surface was on and could not adjust font rasterization for the new display's DPI. Added an `NSWindow.didChangeScreenNotification` observer that re-sends the display ID, content scale, and surface size on every screen transition.

## [2026.2.23] - 2026-03-31

### Changed
- **Token expiry UX for Claude OAuth** — when Claude Code's OAuth token expires or is refreshed (HTTP 401), the app no longer silently retries the keychain read (which triggered repeated macOS permission prompts). Instead, the status bar shows an orange key icon and the usage popover explains the issue with a "Renew" button. Clicking Renew triggers a single, intentional keychain read. Auto-refresh pauses for the affected provider until renewal succeeds.
- **Keychain reads moved off the main thread** — all synchronous `SecItemCopyMatching` calls (in `renewKeychainToken`, `resolveClaudeAuth`, `fetchClaudeUsageViaOAuth`) are now dispatched via `Task.detached` so the macOS keychain permission dialog no longer freezes the UI.

### Added
- `UsageFetchStatus.tokenExpired` and `UsageFetchError.tokenExpired` — new enum cases for the token-expiry state, with dedicated UI handling in both the compact status bar and the detail popover.
- `UsageService.renewKeychainToken(provider:)` — explicit, user-triggered keychain re-read with re-entrancy guard.

### Tests
- Added assertions for `.tokenExpired` in `testUsageFetchStatusEquality` and `testUsageFetchErrorDescriptions`.

## [2026.2.22] - 2026-03-30

### Changed
- **Usage popover opens on click only** — the stats popover no longer appears on hover; it now requires an explicit click on the status bar usage bars. Added a close (X) button to the popover header for dismissal.

## [2026.2.21] - 2026-03-29

### Fixed
- **Keychain permission prompts** — the app no longer repeatedly asks for keychain access. Claude Code OAuth credentials are now cached in the app's own data-protection keychain (`kSecUseDataProtectionKeychain`) after the first successful read, avoiding legacy keychain ACL prompts on every refresh cycle and app relaunch. On 401 (stale token), the cache is automatically invalidated and a fresh token is read from Claude Code's keychain with a single retry.
- **Own keychain items use data-protection keychain** — all `UsageKeychainStore` queries now set `kSecUseDataProtectionKeychain`, preventing legacy keychain prompts when the app is re-signed between builds.

### Changed
- **Usage stats moved to status bar** — usage stats are no longer in the sidebar. Compact colored progress bars (green/orange/red by utilization) now appear in the bottom status bar next to the version label, one per provider. Hovering over the bars reveals a popover with full usage details, provider tabs (segmented picker), metrics, and a refresh button.
- **Removed `UsageStatsView`** — the sidebar usage card, vertical icon tab strip, and `UsageStatsLayout` height calculation have been removed. All rendering logic migrated to `StatusBarUsageView.swift`.
- **Renamed `sidebarProviders` → `statusBarProviders`** on `UsageProvider` to reflect the new display location.

## [2026.2.20] - 2026-03-27

### Fixed
- **TUI app resize on tab switch** — switching to a tab running a TUI app (opencode, codex) no longer causes the terminal to render with an incorrect grid size (tiny text). The root cause was that SwiftUI does not guarantee `NSView.layout()` when a hidden tab's frame expands from zero to full size, leaving `GhosttySurfaceView.contentSize` stale. On tab activation, the surface metrics cache is now invalidated and a layout pass is forced so `ghostty_surface_set_size()` receives correct pixel dimensions.

### Changed
- **Usage stats vertical tab strip** — replaced the horizontal segmented picker (Claude | Codex) with a vertical icon tab strip on the left side of the usage card. Each provider is represented by an SF Symbol (`brain.head.profile` for Claude, `curlybraces` for Codex) with a tooltip on hover showing the provider name. Selected tab uses an accent-colored pill; unselected icons use `primary.opacity(0.5)` for consistent visibility in both light and dark modes.
- **Unified usage card background** — the `appCardColor` background and corner radius now wrap the entire usage block (tab strip + divider + content) instead of the content area alone, giving a cohesive card appearance.
- **Animated tab transitions** — switching between provider tabs now animates with `easeInOut(duration: 0.15)` for a smooth content transition.
- **`UsageProvider.iconName`** — added a computed property to `UsageProvider` returning the SF Symbol name for each provider, keeping icon mapping in the model rather than the view.

## [2026.2.19] - 2026-03-27

### Fixed
- **Sidebar directory tree flicker** — removed premature clearing of directory tree items when the root directory changes, and removed unnecessary child-loading state cleanup in `onDisappear`, eliminating a visual flash when switching directories.

### Changed
- **Claude OAuth credential caching** — Keychain reads for Claude Code OAuth tokens are now cached in a dedicated `ClaudeOAuthCredentialCache`. The cache is invalidated on service stop/reset and when the Claude provider is removed, eliminating repeated `SecItemCopyMatching` calls during auth resolution and usage fetches.
- **Extracted `ClaudeOAuthCredentials` struct** — replaced the inline tuple `(token, subscriptionType, rateLimitTier)` with a named `Equatable` struct for type safety and testability.

### Tests
- Added `ClaudeOAuthCredentialCacheTests` verifying single-load semantics and invalidation behavior.

## [2026.2.18] - 2026-03-26

_Analysis range: `622a851..c5c8e7f` (1 commit, 2 files changed, 18 insertions, 13 deletions)._

### Fixed
- **Usage stats re-fetching on tab/workspace/sidebar switch** — usage data is now fetched once and shared across all tabs, workspaces, and sidebar panels. Switching between them no longer triggers redundant API calls or resets the "updated" timer. `UsageService.ensureStarted()` is idempotent; views are pure readers of the singleton's observable state.
- **Auto-refresh restart after settings change** — `startIfEnabled()` now marks the service as started, preventing `ensureStarted()` from duplicating the fetch cycle when the sidebar view appears after a settings change.

### Changed
- **Usage timestamp format** — the "Updated ..." label in the usage stats card now shows the local time of the last refresh (HH:mm:ss) instead of a relative duration that did not auto-update.

## [2026.2.17] - 2026-03-25

_Analysis range: `cd737c50351b159d0e003a5c10d31db323da44a6..19ca5df` (1 commit, 9 files changed, 266 insertions, 16 deletions)._

### Added
- **Claude submission cooldown service** — added `ClaudeCooldownService`, a shared app-side guard for Claude terminal sessions that blocks repeated plain Enter submissions for 180 seconds and returns human-readable remaining time.
- **Cooldown warning overlay** — Claude tabs now show a temporary inline warning banner when a blocked submission is attempted, with automatic dismissal after a short delay.
- **SwiftPM coverage for cooldown service** — added `ClaudeCooldownService.swift` to `Package.swift` so the new behavior is covered by `swift build` and `swift test`.

### Changed
- **Terminal submit-gate plumbing** — `GhosttyTerminalViewRepresentable`, `StandaloneTerminalView`, and `GhosttySurfaceView` now support a synchronous `onSubmitGate` callback that can block plain Enter before it is forwarded to the terminal session.
- **Usage stats card sizing** — extracted shared `UsageStatsLayout.contentHeight(forSidebarHeight:)` and increased the sidebar usage card height slightly to improve readability.

### Fixed
- **Accidental duplicate Claude submits** — rapid repeat Enter presses in Claude tabs are now intercepted before they reach the underlying session.
- **Stale terminal callback wiring** — `TerminalView.updateNSView` now reapplies callbacks during SwiftUI updates, preventing submit-gate and terminal event closures from drifting out of sync.

### Tests
- Added `ClaudeCooldownServiceTests` (6 tests) covering first submission, cooldown blocking, exact boundary behavior, reset behavior, shared-instance blocking, and remaining-time formatting.
- Added `UsageModelsTests` additions (2 tests) covering the shared usage stats layout height rules.

## [2026.2.16] - 2026-03-25

_15 files changed, ~2750 insertions._

### Added
- **Provider usage stats in sidebar** — new "Usage" section in the Working Directory sidebar tab shows real-time session and weekly rate limits for Claude and Codex (OpenAI/ChatGPT). Always visible on every tab with a Claude | Codex segmented picker. Content area has fixed height (1/4 sidebar) with scrolling.
- **Claude usage via OAuth** — reads Claude Code OAuth credentials from macOS Keychain (`Claude Code-credentials`), calls `api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`. Shows session (5h) and weekly (7d) utilization percentages with reset countdowns, model-specific windows (Sonnet/Opus), and extra usage spend. Falls back to `ANTHROPIC_API_KEY` admin API or browser session import.
- **Codex usage via ChatGPT backend** — reads Codex CLI OAuth tokens from `~/.codex/auth.json` (supports both API key and ChatGPT OAuth `tokens.access_token` modes), calls `chatgpt.com/backend-api/wham/usage` with `ChatGPT-Account-Id` header. Shows plan, session and weekly utilization with reset countdowns, and credit balance.
- **Keychain-backed secret storage** — `UsageKeychainStore` stores imported browser session keys in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Secrets are never persisted in `config.json`.
- **Usage settings section** — new "Usage" tab in Settings with enable/disable toggle, experimental source opt-in, browser session import (with input validation), refresh interval picker (1m–30m or manual), and clear data/auth actions.
- **Usage domain models** — `UsageProvider` (claude, codex, opencode), `UsageSourceKind` (apiKey, cliOAuth, browser, experimental), `UsageAuthSource`, `UsageFetchStatus`, `UsageSnapshot`, `UsageMetric`, `UsagePreferences`. All non-UI types are SwiftPM-covered.
- **26 new tests** — model types, preferences coding, token formatting, provider mapping, Anthropic/Claude console/Codex response parsing, snapshot equality, API response model decoding.

### Security
- All HTTP header values (OAuth tokens, session keys, account IDs) validated for CRLF/null injection before use.
- `responseBodyPreview` only extracts error `type`/`message` fields from API responses — never logs raw bodies that could contain tokens.
- Browser/private source flows are opt-in only and clearly labeled as experimental in both code and UI.
- Imported session keys are sanitized (trimmed, control characters rejected) at import time and at fetch time.

### Changed
- `SettingsSection` — added `.usage` case with `chart.bar` icon.
- `AppConfig` — added `usagePreferences: UsagePreferences` with resilient decoding.
- `SidebarView` — `UsageStatsView()` inserted between `DirectoryTreeView` and `ProjectDocsView`.
- `Package.swift` — added `UsageModels.swift`, `UsageKeychainStore.swift`, `UsageService.swift` to SwiftPM sources.
- `Logger` — added `.usage` category for all usage-related OSLog output.

## [2026.2.15] - 2026-03-21

_Analysis range: `092e83b..HEAD` (3 commits, 6 files changed, 198 insertions, 75 deletions)._

### Added
- **Workspace drag-drop reordering** — workspaces in the sidebar can now be reordered by dragging. Uses `swapAt` semantics with a cooldown flag to prevent double-swaps caused by SwiftUI re-rendering views through the cursor during animation. Added `AppState.swapWorkspaces(_:_:)` and `WorkspaceReorderDropDelegate`.

### Fixed
- **Terminal scroll jump on tab switch** — switching to a tab where Claude CLI is running no longer causes a scroll-to-top-then-bottom artifact. Root cause: `updateNSView` called `ghostty_surface_set_focus` on every SwiftUI view update (not just tab transitions), causing libghostty to re-evaluate the viewport scroll position. Fix: focus changes are now gated to actual `isTabActive` transitions only.

### Changed
- **CLAUDE.md cleanup** — removed all stale references to the Chat subsystem (removed in 2026.2.14): Chat Tabs data flow diagram, 6 Chat Key Components entries, Chat/ directory structure, Chat Engine Notes section, OpenCode chat specifics section, and `MockChatTransport` test reference. Fixed "Adding a New Agent" step 5 to reference `Tab.swift` instead of deleted `ChatComposerStatusBar.swift`.

### Tests
- Added 6 workspace reorder tests: adjacent swap, non-adjacent swap, same-id no-op, invalid-id no-op, active workspace preservation, and step-by-step downward drag simulation.

## [2026.2.14] - 2026-03-20

_Analysis range: `53ff684..HEAD` (7 commits, 90 files changed, 1787 insertions, 9241 deletions)._

### Removed
- **Native chat subsystem** — removed the entire `Chat/` directory (38 source files, 5 test files): `ChatState`, `ChatSessionEngine`, `ChatTransport`, `ClaudeCLITransport`, `OpenCodeCLITransport`, stream parsers, markdown renderer, tool views, message bubble views, chat composer, and `ChatSessionStore`. OpenCode CLI is now the sole multi-provider backend; all AI interaction happens through terminal-mode tabs.
- **Chat-related settings and config** — removed `ChatSendKey`, `ChatRenderMode`, `ChatMessageTextSize` enums; removed `ChatSettingsTab`, `ChatSidebarView`, and `supportsChatMode` agent property. Removed corresponding `AppConfig` fields and resilient decoding entries.
- **`.chat` tab mode** — removed `TabMode.chat`, `createChatTab()`, `createChatTabInSplit()`, `ShortcutAction.newChatTab`, and `.claudeChat`/`.opencodeChat` launch types. Default tab mode changed from `.chat` to `.terminal`.
- **`StatsParser` and `UsageStats`** — removed the token/cost stats parser and its 290-line test suite; live usage tracking was specific to the removed chat subsystem.
- **Chat test infrastructure** — removed `ChatSessionEngineTests`, `ChatSessionStoreTests`, `OpenCodeStreamEventParserTests`, `StreamEventParserTests`, `UsageStatsTests`, `StatsParserTests`, and `MockChatTransport`.

### Changed

#### Performance — subprocess execution
- **`GitProcessRunner`** — replaced thread-blocking pipe reads with a timeout-aware async execution path using `DispatchSemaphore` + deadline. Git subprocesses now terminate and are reaped on cancel or timeout instead of blocking indefinitely. Added `GitProcessResult` value type with structured stdout/stderr/exit status.
- **`OpenCodeCLIService`** — replaced `DispatchSemaphore`-based synchronous model loading with the same timeout-aware async path. Extracted pure model-line parsing into a testable `parseModelLine(_:)` helper; deduplication and malformed-line handling are now covered by unit tests.

#### Performance — Explorer sidebar
- **`DirectoryTreeManager`** — moved directory scanning and sorting onto a background-friendly async API returning value types; results publish back on the main actor. Icon resolution is cached per file path via `NSCache` during tree loading instead of calling `NSWorkspace.shared.icon(forFile:)` during row rendering.
- **`DirectoryTreeScanner`** — extracted as a new SwiftPM-testable module with `scanDirectory()` async API, stable `FileItem.id` identity, child lazy-loading with cancellation, and a configurable visible-item limit.
- **Sidebar file tree** — replaced index-based rendering with `FileItem.id` identity and switched to a cancellable task-based loader keyed by `rootDirectory`.

#### Performance — terminal rendering
- **Ghostty resize deduplication** — added `GhosttySurfaceMetricsCache` that tracks last surface size and content scale; `ghostty_surface_set_size` and `ghostty_surface_set_content_scale` are skipped when the effective values have not changed.
- **Activity detection sampler** — rewrote `ActivityDetectionGate` as a versioned single-in-flight latest-wins sampler. Only one viewport read and one ANSI-strip task can be active at a time; stale scheduled reads are skipped.
- **Ghostty callback coalescing** — `GhosttyApp.requestTick(runImmediatelyIfPossible:)` with `drainTicks()` loop coalesces callback-driven wakeups. `GHOSTTY_ACTION_RENDER` inlines `ghostty_surface_draw` when already on the main thread.

#### Performance — revision graph
- **Latest-wins loading** — added a `graphGeneration` counter checked after every `await` in `loadInitialBatch()`, `loadMore()`, `loadCommitDetails()`, and `loadSelectedFileDiff()`. Stale results from prior refresh/pagination cycles are discarded. `loadMore()` captures `loadedCount` locally to prevent a concurrent reload from corrupting the skip offset.
- **Cancellation-aware lane computation** — replaced `Task.detached` in `computeLanes` with `withCheckedContinuation` on a background queue, so the caller's `Task.isCancelled` checks apply around it.

#### Performance — status bar and git
- **Status bar branch refresh** — removed `isTerminalBusy` from `GitBranchRefreshContext`; the status bar no longer re-fetches the git branch on every terminal busy/idle flip, only on tab or directory changes.
- **Batched `getRepositorySummary`** — all four git subprocess calls (commit count, author count, root commit date, current branch) now run concurrently via `async let`. Replaced the separate `countAuthors` shortlog call with `countAuthorsFromShortlog` that reuses already-fetched output. Replaced two sequential `firstCommitDate` calls with a single `git log --reverse --format=%ai --max-parents=0 --all`.

#### Performance — config and window
- **Non-invalidating window state** — window-frame persistence now uses `@ObservationIgnored` backing storage with a dedicated `saveWindowFrame(_:)` method. Window move/resize events no longer mutate the observable `config` tree, eliminating repeated SwiftUI view invalidation during dragging.

#### Performance — external app lookups
- **Cached app snapshots** — `ExternalApp` now resolves `appURL` and `appIcon` once at init instead of calling `NSWorkspace.shared.urlForApplication` on every view render. `installedApps` and `installedEditorApps` are stored properties computed once at singleton creation.

#### Performance — hidden tab layout
- **Zero-frame hidden tabs** — `TerminalContainerView` now gives hidden tabs (inactive workspace or non-active in single/split mode) a zero frame so they don't participate in SwiftUI layout, while keeping view identity alive for PTY lifetime.

#### Settings and UI
- **Settings cleanup** — removed Chat settings tab, chat-related appearance settings, and legacy native agent configuration entries.
- **Simplified sidebar** — removed chat-mode sidebar content (`ChatSidebarView`); sidebar now shows only terminal/git-relevant panels.
- **Startup page** — removed chat launch types (`.claudeChat`, `.opencodeChat`); startup flow is terminal-only.
- **`ChatModelMode.swift`** moved from `Chat/Models/` to `Models/` (kept for OpenCode terminal-mode model/mode selection).

### Tests
- Added `GitProcessRunnerTests` (4 tests) for timeout, cancellation, trimmed output, and stdout+stderr capture.
- Added `OpenCodeCLIServiceTests` (4 tests) for duplicate models, invalid rows, empty output, and sorted order.
- Added `GhosttySurfaceMetricsCacheTests` (4 tests) for size deduplication, zero-size rejection, content-scale tolerance, and reset.
- Added `ActivityDetectionGateTests` (5 tests) for latest-wins scheduling, in-flight rescheduling, cancel, stale-result rejection, and stale-completion handling.
- Added `DirectoryTreeScannerTests` (7 tests) for async scanning, sort order, recursive scripts/ scan, shallow root scan, file type filtering, and visible-item limit.
- Added `GitStatsServiceTests` additions (2 tests) for `countAuthorsFromShortlog` normal and empty input.
- Added `AppConfigTests` additions (2 tests) for `WindowState` round-trip and nil-default decoding.
- Updated `AppStateWorkspaceTests` to validate that git branch refresh context is stable across busy/idle transitions.
- Removed 5 chat-related test files (1632 lines).

## [2026.2.13] - 2026-03-18

_Analysis range: `e98cac7..70f6895` (1 commit, 1 source file changed, 17 insertions, 6 deletions)._

### Fixed
- **Workspace switch destroys other workspaces' terminal sessions** — closing a workspace (or emptying its tabs) caused all PTY sessions across every workspace to be killed. `TerminalContainerView` used an `if/else` branch on `visibleTabs.isEmpty` that replaced the entire tab ZStack with `EmptyTerminalView`, removing all `GhosttySurfaceView` instances from the view tree and triggering `destroySurface()`. The tab ZStack is now always rendered, with the empty state overlaid on top when the active workspace has no visible tabs.
- **Stale split layout on empty workspace** — when the active workspace had no tabs, a lingering `activeSplitState` could still activate the split layout path. The split branch is now guarded by `!isEmpty` to force single layout when there are no visible tabs.

## [2026.2.12] - 2026-03-17

_Analysis range: `dc5de5c..82068d2` (1 commit, 8 source files changed, 367 insertions, 35 deletions)._

### Changed
- **ANSI stripping moved off main thread** — `GhosttySurfaceView.handleViewportChange()` and `refreshViewportSnapshot()` now dispatch `ANSIStripper.strip()` to a background `DispatchQueue.global(qos: .utility)` and bounce results back to main, eliminating main-thread stalls during heavy terminal output.
- **Chat session disk writes moved to background queue** — `ChatSessionStore` debounced snapshot flushes now execute on a dedicated serial `DispatchQueue(label:..., qos: .utility)`. `saveImmediately()` (app-termination path) remains synchronous to guarantee data persistence.
- **Chat auto-scroll throttled to 10 Hz** — `ChatMessageListView` now gates streaming auto-scroll updates with a 0.1s minimum interval via `lastAutoScrollDate` state, and removes `withAnimation` wrappers from scroll calls to reduce per-character animation overhead.
- **Telegram output poller ANSI stripping offloaded** — `TerminalOutputPoller` now runs `ANSIStripper.strip()` and `ViewportDiffer.diffLines()` inside `Task.detached`, keeping the polling actor's cooperative thread pool free.
- **Window title observer corrected** — `MainView` now triggers `updateWindowTitle()` on `activeWorkspaceID` changes instead of `visibleTabs.count`, ensuring the title updates correctly on workspace switches.

### Fixed
- **OpenCode metadata export hang** — `ChatState.reconcileMetadata()` now wraps `process.waitUntilExit()` in a 5-second `DispatchSemaphore` timeout; previously the call could block indefinitely if the `opencode export` process stalled.
- **Redundant `@Observable` notifications on terminal state** — `Tab.markTerminalBusy()` and `markTerminalIdle()` now guard against setting the same value, avoiding unnecessary view invalidations when the terminal is already in the target state.

## [2026.2.11] - 2026-03-14

_Analysis range: `8d0aaee..b8903b4` (13 commits, 24 files changed, 3747 insertions, 125 deletions)._

### Added
- **Make Commit sub-tab** — full Git staging and commit interface inside the Git client tab.
  - Hierarchical sidebar with staged and unstaged file sections, collapsible folder tree, and file status badges (M/A/D/R/?).
  - Side-by-side diff viewer with line numbers, color-coded additions/deletions/modifications, and horizontal scrolling for long lines.
  - Commit message composer with live character count (warns at 72+), amend mode (soft-resets HEAD~1 and restores the previous message), and commit/amend button.
  - Double-click a file to stage or unstage it; double-click a folder to stage/unstage all descendant files in a single batch git operation.
  - Right-click context menu with Stage/Unstage, Discard Changes, and Delete Untracked File actions (destructive actions require confirmation dialog).
  - New Branch sheet with branch name validation (rejects `..`, spaces, `~^:?*[\`, control chars, leading/trailing dots and slashes).
  - Push current branch button in the toolbar.
  - Fallback diff loading: when `git diff` returns empty for a valid text file, loads content via `git show :path` (staged) or direct file read (unstaged).
- **Revision graph diff viewer** — selecting a commit in the revision graph now shows a side-by-side diff pane with the same rendering as the Make Commit tab.
- **CloseButton shared component** — reusable close button with circular gray hover highlight, used in tab bar and workspace sidebar for consistent close affordance.
- **Git working tree service** (`GitWorkingTreeService`) — async service for staging, unstaging, committing, pushing, branch creation, soft reset, discard, delete, diff loading, and snapshot loading via `git status --porcelain=v1`.
- **Git working tree models** — `GitScopedChange`, `GitWorkingTreeSnapshot`, `GitChangeSection`, `GitStatusColumn`, `GitDiffDocument`, `GitDiffRow`, `MakeCommitComposerState`, and supporting types.

### Changed
- `GitProcessRunner` expanded with additional helper methods for working tree mutations (stage, unstage, reset, checkout, branch, push).
- `GitStatsService` expanded with commit diff retrieval for the revision graph viewer.
- `RevisionGraphView` refactored with full-width diff pane fix using `GeometryReader` + `.frame(minWidth:)` to prevent content from collapsing inside `ScrollView([.vertical, .horizontal])`.
- Tab bar and workspace sidebar close buttons now use the shared `CloseButton` component with hover highlight.
- `GitTab` enum updated: `.commit` sub-tab is no longer a stub.

### Fixed
- **Diff viewer width collapse** — `ScrollView([.vertical, .horizontal])` content no longer shrinks to intrinsic width in both the revision graph and make commit diff panes.
- **"No textual diff available" for valid files** — added fallback diff loading when `git diff` returns empty output for staged or modified text files.
- **`hasUnstagedEntry` redundant predicate** — removed logically redundant `|| workTreeStatus == .untracked` condition in `GitScopedChange`.
- **Amend toggle race condition** — rapid toggling of amend mode no longer interleaves `enterAmendMode`/`exitAmendMode` calls (guarded by `isRunningMutation`).
- **Diff context size** — changed from `-U99999` to bounded `-U10000` to limit diff output for very large files.
- **Sidebar file list performance** — switched from eager `VStack` to `LazyVStack` so only visible rows are rendered.

### Tests
- Added `GitDiffParserTests` (5 tests) covering side-by-side diff row generation from unified diff output.
- Added `GitWorkingTreeServiceTests` (20 tests) covering branch name validation, status line parsing, and snapshot construction.
- Added `MakeCommitComposerStateTests` (7 tests) covering single-line input normalization and commit message formatting.

## [2026.2.10] - 2026-03-13

_Analysis range: `11a2df3..6cd5112` (1 commit, 12 files changed, 728 insertions, 9 deletions)._

### Added
- **Terminal tab command labels** — plain terminal tabs now show the last submitted command in the tab title (e.g., "npm | cli" instead of "Terminal | cli").
  - Added `TerminalCommandCaptureBuffer` — a best-effort keystroke shadow buffer that tracks typed input, backspace, Ctrl+C/U/W clear, and paste to approximate the current command line.
  - Added `Tab.commandLabel(from:)` — a shell-aware command parser that tokenizes quoted strings, skips environment assignments (`FOO=1`), wrapper commands (`sudo`, `env`, `command`) with their options, and normalizes absolute paths to base names.
  - Added `onCommandSubmitted` callback wired from `GhosttySurfaceView` through `TerminalView` to `Tab.updateLastSubmittedCommandLabel(from:)`.
  - AI agent tabs (Claude, OpenCode) are unaffected and keep their static labels.
- **Empty workspace retargeting** — creating a tab in a new directory while the active workspace has no tabs retargets the workspace to the new directory instead of leaving it stale.
  - If another workspace already exists for the target directory, the empty workspace is removed and the existing one is activated.
  - Added `resolvedActiveWorkspaceID(for:)` and `retargetWorkspace(id:to:)` private helpers in `AppState`.

### Changed
- `GhosttySurfaceView` now tracks command capture state across keyboard input, paste (Cmd+V), text injection, and control signals (Ctrl+C clears the buffer).
- `GhosttySurfaceView.injectText` refactored to use shared `writeTextToSurface` helper, avoiding duplicated `ghostty_surface_text` calls.
- `Tab.commandLabel(from:)` and its static helpers are `nonisolated`, allowing off-MainActor usage for pure parsing.

### Tests
- Added `TabLabelTests` (9 tests) covering default labels, command reflection, AI tab immunity, parser tokenization, path normalization, env-var skipping, wrapper command handling, and quoted paths.
- Added `TerminalCommandCaptureBufferTests` (5 tests) covering newline submit, paste without auto-submit, backspace, clear, and word deletion.
- Added workspace retargeting tests in `AppStateWorkspaceTests` (6 tests) covering retarget on terminal/chat/git tab creation, reuse of existing workspace, orphan cleanup, and non-empty workspace preservation.

## [2026.2.9] - 2026-03-11

_Analysis range: `54b9879d44fcb545b2810b6387aa054b377ffc90..d32d81d` (7 commits, 43 files changed, 3995 insertions, 764 deletions)._

### Added
- **Git client tab** with repository overview and revision graph views.
  - Added `GitTab`, `GitStats` models, `GitProcessRunner`, `GitStatsService`, and `GraphLaneCalculator` for commit graph parsing, repository metrics, and lane assignment.
  - Added `GitClientView` and `RevisionGraphView` for browsing repository stats and commit history inside the app.
- **Reusable startup session flow** in `StartSessionContentView`.
  - Added a richer launch flow with working-directory selection, recent folders, and launch-type-specific session creation in a standalone view reused by the startup page and empty workspace state.
- **Workspace tab improvements**.
  - Added numbered workspace tab labels and numbered close-confirmation text.
  - Added draggable tab reordering within a workspace, trailing-drop support, insertion indicators, and drag-cancel restoration.
- **SwiftPM GitHub Actions workflow**.
  - Added a `SwiftPM` CI lane that runs `swift build` and `swift test` without requiring Ghostty.

### Changed
- **Startup page architecture** now uses the extracted `StartSessionContentView` instead of keeping the full session-creation UI inline.
- **Workspace directory defaults** are now resolved from the active workspace/tab context before falling back to older global working-directory state.
- **Bottom status bar branch display** now refreshes based on active tab execution context, not only directory changes.
- **README and CLAUDE guidance** now document the SwiftPM-covered versus Xcode-only boundary more explicitly.
- **Website/docs assets** refreshed, including updated screenshots and icon assets.

### Fixed
- **New workspace tab launches** now use the workspace's root folder instead of incorrectly inheriting the previous workspace's folder.
- **Automation and Telegram directory fallback** now respects the active workspace/tab context instead of stale global directory state.
- **Bottom bar git branch label** now updates after in-repo branch changes such as `git checkout`.
- **Tab drag cancellation** now restores the original workspace tab order if the drag ends without a valid drop.

### Tests
- Added test coverage for:
  - workspace-specific directory resolution,
  - git branch refresh context,
  - numbered tab labels and close-confirmation labels,
  - workspace tab reordering and drop-indicator behavior,
  - git stats parsing and graph lane calculation.

## [2026.2.8] - 2026-03-09

_Analysis range: `baec6b578f3a9cd971866e6777592d3e6623cb6f..79ecb8e` (4 commits, 19 files changed, 385 insertions, 51 deletions)._

### Added
- **Terminal activity tracking** in `Tab` with auto-idle timeout.
  - `recordTerminalActivity()` marks a tab busy and auto-resets to idle after 800ms of no further output.
  - `handleTerminalCommandEntered()` combines command-count increment with activity recording.
  - `handleTerminalLaunch(shouldAutoRunCommand:)` marks AI agent tabs busy immediately on launch.
- **`onTerminalActivity` callback** on `GhosttySurfaceView` and `StandaloneTerminalView`, fired whenever the terminal viewport snapshot changes.
- **`ActivityDetectionGate`** service to prevent render-driven background-activity checks from being endlessly rescheduled.
- **Equal-width tab layout** in `TabBarView` using `GeometryReader` so tabs share available space evenly instead of being intrinsically sized.
- **Separate debug app icon** (`AppIconDev`) used for Debug builds, so dev and release builds are visually distinguishable in the Dock.
- **`KNOWN_ISSUES.md`** documenting that tab activity status does not yet reliably reflect ongoing AI agent work.

### Changed
- **App icon asset** replaced (`SlothyTerminalIcon.jpg` → `STIcon.jpg`).
- **Version bump** to 2026.2.8 (build 10).
- **Website (`docs/`)** updated to reflect the current feature set:
  - "Background Task Queue" → "Workspace-Aware Navigation", "Risky Tool Detection" → "Automation Sidebar", "Ask Mode & Smart Routing" → "Telegram Relay Sidebar".
  - Added "Prompts, Docs, and Activity Signals" feature card.
  - Added hero workflow pills (Workspaces, Automation, Awareness, Telegram).
  - Updated meta description, carousel captions, and Open Graph tags.
- **README** now links to `KNOWN_ISSUES.md`.

### Tests
- Added `ActivityDetectionGateTests` (3 tests) for schedule gating, finish, and cancel behavior.
- Added `TabActivityTests` (4 tests) covering command entry, auto-run launch idle settling, interactive launch staying idle, and activity refresh extending the busy window.

## [2026.2.7] - 2026-03-07

_Analysis range: `16c106d650777e3d7da29f23ca21b9a2e0d12bbe..working-tree` (17 commits + local changes, 86 files changed, 5502 insertions, 4565 deletions)._

### Added
- **Workspaces** as first-class project containers.
  - Added `Workspace` model and workspace-aware tab selection/routing in `AppState`.
  - Added dedicated Workspaces sidebar for creating, switching, and removing workspaces.
  - Added `visibleTabs` filtering so workspace switching scopes the visible tab set without destroying background sessions.
- **Terminal injection subsystem** for programmatic input delivery into live terminal tabs.
  - Added `InjectionPayload`, `InjectionRequest`, `InjectionTarget`, `InjectionResult`, and `InjectionEvent`.
  - Added `InjectionOrchestrator` with per-tab FIFO queues, timeout handling, and request lifecycle tracking.
  - Added `TerminalSurfaceRegistry` and `InjectableSurface` support for locating live Ghostty surfaces.
- **Automation / Scripts sidebar**.
  - Added `ScriptScanner` for discovering `.py` and `.sh` files in the project root and `scripts/`.
  - Added `AutomationSidebarView` for browsing scripts, opening them in editors, revealing them in Finder, copying paths, and inserting relative paths into the active terminal.
  - Added double-click insertion for script paths and hover affordances on script rows.
- **Prompts sidebar** for quick prompt reuse.
  - Added sidebar list of saved prompts with tag display, quick edit, and double-click / context-menu paste into the active terminal via bracketed paste.
- **Telegram relay architecture**.
  - Added `TelegramRelaySession`, `TerminalOutputPoller`, and ANSI stripping / viewport diffing support for relaying live terminal output back to Telegram.
  - Added relay commands and tab targeting flow so Telegram can attach to active Claude/OpenCode terminal tabs or selected relayable tabs.
- **Background terminal activity indicator** in tabs.
  - Added unseen-output tracking and a small badge for inactive tabs when new terminal output appears.

### Changed
- **Telegram bot lifecycle** moved from a dedicated tab mode to a sidebar-owned runtime.
  - Removed `.telegramBot` tab mode and related tab-specific runtime handling.
  - Telegram now runs as a sidebar service with status, counters, timeline, and activity log.
- **Sidebar information architecture** was reorganized.
  - Added Workspaces, Prompts, Automation, and Telegram sidebar panels.
  - “Project docs” remains part of the Working directory sidebar and was moved into its own lower section, replacing Session Info for terminal/agent sidebars.
- **Working directory + tab behavior** is now workspace-aware.
  - Tab bar uses `visibleTabs` while terminal containers continue to keep all sessions alive in the background.
  - Closing an active tab now prefers another tab from the same workspace.
- **Settings navigation** now supports section preselection through native Settings window routing.
- **Startup / app flow** continues moving toward workspace- and sidebar-driven navigation rather than task-queue-centric flows.

### Fixed
- **Terminal background activity detection** now tracks unseen output on inactive tabs and clears the badge when the tab becomes active.
- **Script insertion UX** improved.
  - Relative script paths can be pasted directly into the active terminal.
  - Shell scripts preserve `./` when appropriate for local execution.
- **Terminal focus / responder handling** improved in Ghostty-backed views, including better first-responder restoration and surface registration.
- **Project docs placement** in the Working directory sidebar is now separated from session metrics.
- **Telegram Start Bot button** is temporarily disabled pending start-flow design clarification, without removing Telegram functionality.

### Removed
- **Task Queue subsystem**.
  - Removed task queue state, orchestrator, runners, storage, risky tool detector, queue panel, composer/detail/task row views, and related tests.
  - Removed Telegram prompt-executor integration that depended on task execution / enqueue flows.
- Removed obsolete Automation placeholder view in favor of the real Scripts sidebar.
- Removed `FEATURES.md`.

### Tests
- Added tests for:
  - workspace lifecycle and tab scoping,
  - injection requests and orchestrator behavior,
  - terminal surface registry behavior,
  - script scanning,
  - Telegram relay runtime behavior and startup statement generation.
- Removed tests tied to the deleted Task Queue subsystem.

### Docs
- Updated `CLAUDE.md` with workspace architecture, injection subsystem, Telegram relay behavior, and sidebar-related implementation notes.
- Added `docs/fix-driven-development.md`.
- Updated `README.md` and package/source wiring to reflect the current architecture.

## [2026.2.6] - 2026-02-28

_Analysis range: `b085f3c2cf16d4b325a145da6a02f43347b3fbb9..0cc1493` (24 commits, 66 files changed, 5456 insertions, 4433 deletions)._

### Added
- **Telegram Bot subsystem** with a dedicated tab mode (`.telegramBot`) and full runtime stack.
  - New API layer: `TelegramBotAPIClient`, Telegram response/request models, and message chunking for long replies.
  - New runtime orchestration: polling loop with exponential backoff, allowed-user authorization checks, command routing, execution/passive modes, and activity/event tracking.
  - New command flow support: `/help`, `/show_mode`, `/report`, `/open_directory`, `/new_task` and multi-step interaction state.
  - New Telegram UI: status/counters/controls bars, activity log, timeline, and host `TelegramBotView`.
  - New Telegram settings tab for bot token, allowed user, execution agent, auto-start, reply prefix, and `/open-directory` configuration.
- **Startup Page flow** replacing the previous agent selection modal.
  - Unified session creation flow with folder selection, launch type picker, prompt picker, and launch availability hints.
  - New launch types via `LaunchType`: `terminal`, `claude`, `opencode`, `claudeChat`, `opencodeChat`, `telegramBot`.
  - Persisted startup defaults (`lastUsedLaunchType`) and shared folder preselection.
- **OpenCode startup options for terminal launches**.
  - OpenCode mode selector (Build/Plan) and model picker on startup.
  - Startup launch now maps options to CLI args (`--model`, `--agent plan`, `--prompt`) and passes them through `launchArgumentsOverride`.
  - New shared `OpenCodeCLIService` for model discovery (`opencode models`) reused by startup/chat flows.
- **Prompt management improvements**.
  - Added reusable `PromptTag` model and prompt-to-tag assignment (`tagIDs`).
  - Prompts settings converted to a table-style workflow with tag management sheet, tag cleanup, and 50-character preview text.
  - Prompt picker upgraded to richer menu rows with previews.
- **Sidebar Project Docs block** in Explorer/Stats sidebars.
  - New `ProjectDocsView` listing `README.md`, `AGENTS.md`, and `CLAUDE.md` when present.
  - Resolves repo root through Git when available and provides quick open/edit actions.
- **Tab execution indicator** in tab bar.
  - Added animated executing indicator and tab-level execution state across chat, terminal, and Telegram modes.

### Changed
- **Session creation UX** now centers around “New Session” instead of multiple menu-specific new-tab actions.
  - App menu and dock menu now open the startup flow.
  - Empty state CTA now routes to startup page.
- **App/tab state model expanded**.
  - `TabMode` now includes `telegramBot`.
  - `Tab` now supports `launchArgumentsOverride`, terminal busy/executing state, and optional `telegramRuntime`.
  - `AppState` now supports Telegram bot tab lifecycle, startup modal routing, and Telegram delegate bridge hooks.
- **Config model and loading hardened**.
  - `AppConfig` gained startup/OpenCode/Telegram/tag-related fields and resilient decoding coverage.
  - `ConfigManager` now suppresses save-on-load churn to avoid unnecessary disk writes.
- **Settings IA updated**.
  - Added dedicated Telegram section.
  - Prompt settings reworked for table + tags.
  - General/agents settings aligned to current CLI-first launch and execution flows.
- **Build/package wiring updated**.
  - `Package.swift` explicit source list now includes `LaunchType`, `OpenCodeCLIService`, and Telegram subsystem files.
- **Version bump** to `2026.2.6` (build `8`).

### Fixed
- **macOS keypress alert sound** for Enter/Backspace in terminal view by consuming AppKit command selectors in `GhosttySurfaceView.doCommand(by:)`.
- **Terminal execution state reset** on command completion and surface close via Ghostty `GHOSTTY_ACTION_COMMAND_FINISHED` callback wiring.
- **Config load side effects** reduced by preventing save triggers while loading persisted config.
- **Legacy native-agent config compatibility** retained: removed/old native keys are ignored gracefully during decode.

### Removed
- Deprecated **AgentSelectionView** and associated “new chat/new agent tab” creation flow replaced by Startup Page.
- `AgentFactoryTests.swift` removed and replaced with broader config/launch/Telegram coverage.
- Obsolete planning artifacts/scripts removed:
  - `merged-plan-detailed.md`, `merged-plan.md`, `plan.md`, `opencode-pla.md`, `codex-chat-implementation.md`
  - `scripts/add-test-target.sh`

### Tests
- Added/expanded tests for:
  - `AppConfig` resilient decoding and backward compatibility.
  - `LaunchType` metadata/codable persistence behavior.
  - Saved prompt decoding and tag-aware prompt behavior.
  - Telegram API models, command parsing/handling, message chunking, and runtime behavior.

### Docs
- Updated `CLAUDE.md` architecture notes for Ghostty, OpenCode-first chat transport layering, TaskQueue, and Telegram subsystem coverage.
- Added `FEATURES.md` tracker and expanded README docs index.

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
