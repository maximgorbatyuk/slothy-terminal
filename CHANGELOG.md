# Changelog

All notable changes to SlothyTerminal will be documented in this file.

## [2026.3.13] - 2026-05-15

### Removed
- **Start Session chooser modal is gone.** `Views/StartSessionContentView.swift` (~700 lines) and `Views/StartupPageView.swift` (the sheet wrapper) were the agent/launch-type picker shown on Cmd+T, on the "+" tab button, and as the empty-state body. Every flow that previously routed through them now lands the user in a `.terminal` tab directly — picking an agent up-front was friction nobody asked for once the chat removal landed and OpenCode became the sole smart backend. The corresponding `ModalType.startupPage` / `.startupPageSplit` cases, `AppState.showStartupPage()` / `showStartupPageForSplit()`, and the matching branches in `ModalRouter` are all deleted. (`SlothyTerminal/Views/StartSessionContentView.swift`, `SlothyTerminal/Views/StartupPageView.swift`, `SlothyTerminal/App/AppState.swift:12-25, 691-696`, `SlothyTerminal/Views/MainView.swift:319-339`)
- **`LaunchType` enum and `lastUsedLaunchType` config field deleted.** `Models/LaunchType.swift` and `SlothyTerminalTests/LaunchTypeTests.swift` were entirely about driving the now-removed chooser. The `lastUsedLaunchType: LaunchType?` field on `AppConfig` is also gone — `AppConfig`'s resilient decoder silently ignores the stale key on disk so existing user configs do not error out. `Package.swift` `SlothyTerminalLib` sources list is trimmed accordingly. (`SlothyTerminal/Models/LaunchType.swift`, `SlothyTerminalTests/LaunchTypeTests.swift`, `SlothyTerminal/Models/AppConfig.swift:25-31, 138-141`, `Package.swift:84-88`)

### Added
- **`AppState.selectWorkspace(id:)`** — user-facing wrapper around `switchWorkspace` that auto-creates a `.terminal` tab in the target workspace if it currently has none. The logic is deliberately not inside `switchWorkspace` itself because `createTab` indirectly calls `switchWorkspace` when materialising the first workspace; spawning a tab inside `switchWorkspace` would produce a duplicate tab for every `createTab` call. The new method is wired from `WorkspaceRowView.onSelect`. (`SlothyTerminal/App/AppState.swift:256-275`, `SlothyTerminal/Views/WorkspacesSidebarView.swift:30-32`)
- **`AppState.openGitClientTab()`** — looks up the first `.git`-mode tab in the active workspace and `switchToTab`s to it, or falls back to `createGitTab(directory:)` rooted at `activeWorkspace.rootDirectory` when none exists. Powers the new sidebar Git Client button below. Handles the no-active-workspace edge case by delegating to `currentContextDirectory` so the button is never a no-op when the user has any cwd context. (`SlothyTerminal/App/AppState.swift:402-421`)
- **`SidebarActionIcon` view** in the sidebar tab strip — a non-toggle button that visually mirrors `SidebarTabIcon` (28×28 frame, hover tint, tooltip) but does not participate in the panel selection state. Sits below the three panel icons (Explorer / Prompts / Automation) and is separated by an 18×1pt divider so the eye reads it as an action rather than a fourth panel. The first instance is `arrow.triangle.branch` → `appState.openGitClientTab()`. (`SlothyTerminal/Views/SidebarContainerView.swift:76-114, 116-141`)
- **`OpenFolderWelcomeView`** — the new empty-state card shown in the main content area whenever `visibleTabs.isEmpty`. Renders a folder icon, a context-aware headline ("Open a folder to get started" on cold start, "Pick a folder for this workspace" when an empty active workspace exists), an NSOpenPanel-driven "Open Folder…" primary button, and up to 5 rows from `RecentFoldersManager.shared.recentFolders` as one-click affordances. Selection routes through `appState.createTab(agent: .terminal, directory: url)` — which means `AppState.resolvedActiveWorkspaceID` retargets the active workspace's `rootDirectory` and `name` to the picked folder when the workspace is empty, or falls through to `createWorkspace(from:)` when none exists. The previous neutral "No open tab" placeholder is removed; the same welcome card now covers both cold start and "user just closed the last tab" cases. (`SlothyTerminal/Views/TerminalContainerView.swift:491-682`)
- **Hover state on recent-folder rows in the welcome card.** A `@State private var hoveredFolder: URL?` tracks the row under the cursor; the row's `RoundedRectangle(cornerRadius: 8).strokeBorder(...)` overlay paints `Color.accentColor` at 1.5pt when hovered and `Color.clear` otherwise. The `.onHover` write is guarded (`hovering ? url : (hoveredFolder == url ? nil : hoveredFolder)`) so a stale exit event from a previously-hovered row cannot clear an active hover on an adjacent row. (`SlothyTerminal/Views/TerminalContainerView.swift:514-516, 595-642`)
- **`AppStateWorkspaceTests` — `selectWorkspace` + `openGitClientTab` coverage.** Four new tests: `selectWorkspaceCreatesTerminalTabWhenEmpty` (selecting an empty workspace produces exactly one `.terminal` tab rooted at the workspace dir), `selectWorkspaceKeepsTabsWhenNonEmpty` (re-selecting a workspace with existing tabs restores the prior active tab and adds nothing), `openGitClientTabCreatesNewWhenAbsent` (no existing `.git` tab → one is created in the active workspace at its root), and `openGitClientTabActivatesExisting` (an existing `.git` tab is reactivated, no duplicates). Total SPM tests now 210, all green. (`SlothyTerminalTests/AppStateWorkspaceTests.swift:766-849`)

### Changed
- **Creating a new workspace from the sidebar immediately opens a terminal tab.** `WorkspacesSidebarView.openFolderPickerForWorkspace` now calls `appState.createWorkspaceAndTerminalTab(directory:)` instead of `createWorkspace(from:)`. The path that already existed for the Finder Services "New SlothyTerminal Window Here" entry is now also the path for the in-app sidebar button. (`SlothyTerminal/Views/WorkspacesSidebarView.swift:120-127`)
- **Selecting an existing workspace auto-opens a terminal when the workspace has no tabs.** `WorkspaceRowView.onSelect` now calls `appState.selectWorkspace(id:)` instead of `switchWorkspace(id:)`. A workspace whose last tab was closed (so it shows the welcome card) becomes "live" again on a single click without forcing the user back through the welcome flow. (`SlothyTerminal/Views/WorkspacesSidebarView.swift:30-32`, `SlothyTerminal/App/AppState.swift:256-275`)
- **`NewTabButton` (the "+" in the tab bar) creates a `.terminal` tab directly** rooted at `appState.activeWorkspace?.rootDirectory ?? currentContextDirectory ?? FileManager.default.homeDirectoryForCurrentUser`. Previously it opened the now-removed Start Session sheet. (`SlothyTerminal/Views/TabBarView.swift:365-385`)
- **File menu — Cmd+T and Cmd+Opt+T open a terminal tab directly.** The "New Session…" item is renamed **"New Terminal Tab"** and calls `openNewTerminalTab()` (which routes through `directoryForNewTerminalTab()` using the same workspace-root-first resolution as the "+" button). "New Session in Split View…" (Cmd+Opt+T) becomes **"New Terminal Tab in Split View"** and calls `createTabInSplit(agent: .terminal, …)`. The pre-existing Cmd+Shift+Opt+T entry that pops the folder selector is renamed **"New Terminal Tab in Folder…"** to disambiguate from the new direct-open variant. (`SlothyTerminal/App/SlothyTerminalApp.swift:67-85, 193-206`)
- **`.newSessionRequested` notification now opens a terminal tab directly** instead of presenting the chooser modal, matching the menu behaviour above. (`SlothyTerminal/App/SlothyTerminalApp.swift:34-36`)
- **Git Client is no longer offered as a launch type — it's a sidebar action.** Removing it from the chooser flow means there is exactly one canonical path to a Git tab (the sidebar button), and the find-or-activate-existing semantics in `openGitClientTab` mean repeated clicks no longer pile up multiple Git tabs in the same workspace. (`SlothyTerminal/Views/SidebarContainerView.swift:24-31, 99-104`, `SlothyTerminal/App/AppState.swift:402-421`)
- **`RecentFoldersManager.addRecentFolder(url)` is now called from the sidebar's "New workspace" picker.** Previously only `FolderSelectorModal` recorded selected folders, so workspaces created via the sidebar never appeared in the recent-folders quick-pick list. Both code paths (sidebar new-workspace and welcome-card folder picker) now register the folder before handing off to the workspace/tab creation. (`SlothyTerminal/Views/WorkspacesSidebarView.swift:120-127`, `SlothyTerminal/Views/TerminalContainerView.swift:671-674`)

### Notes
- The auto-tab-on-select / auto-tab-on-create logic lives only in the user-facing wrappers (`selectWorkspace`, `createWorkspaceAndTerminalTab`) — *never* inside `switchWorkspace`. This is the load-bearing invariant for `createTab`'s internal `switchWorkspace` call during first-workspace creation: if a future change re-introduces auto-creation inside `switchWorkspace`, every `createTab(…)` will produce two tabs for one call. The four new tests pin both halves of this (empty-on-select gets a tab, non-empty-on-re-entry does not).
- `OpenFolderWelcomeView` calls `appState.createTab(.terminal, directory:)` for *both* recent-folder rows and the NSOpenPanel result. `resolvedActiveWorkspaceID` is the single chokepoint that decides whether to retarget the empty active workspace, drop-and-reuse a duplicate, or create a fresh workspace — keeping the welcome card on top of that one chokepoint avoids divergent "create vs retarget" branches in the view layer.
- `LaunchType` is deleted, not deprecated. `AppConfig`'s resilient decoder ignores unknown keys, so users with `lastUsedLaunchType` on disk decode cleanly. Verified manually with `swift test`'s `AppConfig` suite (the existing `decodesFullConfig` / `unknownKeysIgnored` tests cover this shape).
- Verified end-to-end with `swift test` (210/210, including the four new workspace tests) and `xcodebuild -project SlothyTerminal.xcodeproj -scheme SlothyTerminal -configuration Debug build CODE_SIGNING_ALLOWED=NO` (BUILD SUCCEEDED). The app was not launched in this session — manual smoke test recommended for: (a) closing the last tab in a workspace and confirming the welcome card appears with recent folders + hover border, (b) picking a folder from the welcome card and confirming the *same* workspace's name updates in the sidebar (not a new workspace), (c) clicking the new Git Client icon in the sidebar tab strip when no Git tab exists and again when one already exists.

## [2026.3.12] - 2026-05-15

### Fixed
- **MiniMax usage popover now reports correct used / remaining numbers.** Despite their names, MiniMax's `current_interval_usage_count` and `current_weekly_usage_count` fields report the **remaining** quota in the window, not the consumed quota — a fresh `MiniMax-M*` row arrives as `usage=4500, total=4500`, which the previous build interpreted as "100% used" when the user has actually consumed nothing. `buildSnapshot` now computes `used = total - usage_count` for both the interval and weekly windows, and the headline-selection fallback (`max-by-utilization`) is inverted to match. The per-model rows in the popover ("speech-hd", "image-01", etc.) also show `used / total` instead of `remaining / total`. The wire field names are kept as-is on the Codable model to mirror the upstream JSON; `MinimaxModelRemains` carries a doc comment warning future readers about the inversion. (`SlothyTerminal/Services/MinimaxUsageProvider.swift:101-185`, `SlothyTerminal/Models/UsageModels.swift:252-286`)
- **Keychain saves no longer fail with `errSecMissingEntitlement (-34018)` on unsandboxed builds.** Three call sites (`UsageKeychainStore.saveString` / `loadString` / `delete`) and the cached-Claude-OAuth helpers in `UsageService` were passing `kSecUseDataProtectionKeychain: true` to `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`. The data-protection keychain requires `application-identifier` or `keychain-access-groups` entitlements, which the app does not carry because `ENABLE_APP_SANDBOX = NO`. The result was a silent save failure for every MiniMax API key, OpenAI access token, and cached Claude OAuth refresh token — the Settings UI accepted the paste, displayed "Connected", but the next fetch couldn't find the key. All five queries are now plain `kSecClassGenericPassword` reads/writes against the legacy file-based keychain, which works without entitlements. (`SlothyTerminal/Services/UsageKeychainStore.swift:19-32, 70-76, 106-112`, `SlothyTerminal/Services/UsageService.swift:528-557, 564-597, 600-610`)
- **Claude popover now surfaces every per-model 7d window the API publishes, not just Sonnet and Opus.** The Anthropic OAuth usage response returns up to five per-model 7d channels (`seven_day_sonnet`, `seven_day_opus`, `seven_day_cowork`, `seven_day_omelette`, `seven_day_oauth_apps`), and any subset may be a JSON `null` for accounts that don't use that channel. The previous build hard-coded only the Sonnet + Opus branches and gated each on `utilization > 0`, so a Cowork-heavy account or a brand-new 7d window at 0% would show nothing. The two `if let` blocks are replaced with a five-entry table iterated in a `for` loop; `mergedClaudeWindow` already returns nil for JSON-null channels (because `NSNull as? [String: Any]` fails), so null entries are naturally filtered without an explicit guard. The `utilization > 0` filter is also dropped, so an active-but-empty 7d window surfaces as "0% used" rather than disappearing. (`SlothyTerminal/Services/UsageService.swift:1076-1099`)

### Changed
- **Status-bar usage popover header is now two rows instead of one.** With four providers (`Claude`, `Codex`, `Cursor`, `MiniMax`), the inline-labelled segmented picker at 320 pt width was squeezing each segment label down to ~8 pt and wrapping one character per line. The header is now a stacked `VStack`: row one is the "Providers" caption + close button, row two is a full-width labels-hidden segmented picker. (`SlothyTerminal/Views/StatusBarUsageView.swift:149-181`)
- **Status-bar usage popover content area uses a fixed 400 pt height instead of `maxHeight: 320`.** The dynamic-height behaviour made the popover jump every time the user clicked through providers because each provider has a different metric count (Claude's per-model 7d list dominates). Fixing the height to 400 pt sizes for the worst case so the popover stays still while scrolling continues to handle overflow. (`SlothyTerminal/Views/StatusBarUsageView.swift:188-201`)

### Added
- **"Turn on usage tracking" button inside the popover's disabled view.** Previously the disabled view's only call to action was the static text "Enable in Settings > Usage", which required the user to actually open Settings to flip the toggle. The view now renders a bordered button that flips `usagePreferences.isEnabled = true` and calls `usageService.startIfEnabled()` in place, so the user can go from cold-open to "live data" without leaving the popover. (`SlothyTerminal/Views/StatusBarUsageView.swift:497-522`)
- **`notConnectedView(provider:)` separates "global tracking off" from "this provider has no credentials".** When global usage tracking is on but a specific provider has no resolved auth source (e.g. user enabled tracking but hasn't pasted their MiniMax key yet), the popover now shows "<Provider> not connected — Add credentials in Settings → Usage → <Provider>" with a `link.badge.plus` icon, instead of the misleading "Usage tracking is off" copy. The decision is gated on `ConfigManager.shared.config.usagePreferences.isEnabled`. (`SlothyTerminal/Views/StatusBarUsageView.swift:204-216, 525-547`)
- **Settings → Usage → MiniMax gains "Fetch Usage" and "Test Connection" buttons.** Two new buttons sit beside "Clear Saved Key": "Fetch Usage" runs the full `UsageService` fetch chain (the same path the status bar reads from) and reports back the resolved status + snapshot inline; "Test Connection" bypasses the service layer and calls `MinimaxUsageProvider.fetchUsage` directly, so the user (and bug reports) can isolate API/auth issues from SwiftUI / Observable plumbing issues. Outcomes render below the button row, prefixed `✓` / `…` / `✗` with green/orange/red colouring. (`SlothyTerminal/Views/SettingsView.swift:1112, 1219-1232, 1235-1241, 1413-1485`)
- **Settings → Usage `.onAppear` re-resolves auth sources and refetches MiniMax.** Catches the case where the app launched without a MiniMax key in Keychain (so `.minimax` was absent from `resolvedSources`), the user later saved a key, but the save-time fetch somehow didn't reach the status bar. Reopening Settings is a no-op when everything is already wired correctly and a recovery path when it isn't. (`SlothyTerminal/Views/SettingsView.swift:1248-1263`)
- **Verbose diagnostic logging through the MiniMax fetch chain.** Every step — `saveMinimaxKey` entry, Keychain save result, `resolveMinimaxAuth` outcome, `fetchMinimaxUsage` entry, key load, HTTP send, response status, decode outcome, parsed row count — now logs to `Logger.usage`. HTTP non-2xx responses additionally log a 200-300 character body preview, and decode failures log a 300-character body preview, so payload-shape regressions are debuggable from Console.app without rebuilding. (`SlothyTerminal/Services/MinimaxUsageProvider.swift:18-92`, `SlothyTerminal/Services/UsageService.swift:386-398, 1798-1815`, `SlothyTerminal/Views/SettingsView.swift:1370-1396`)
- **MiniMax responses are captured into `ProviderResponseStore`.** The same in-memory "Latest JSON Responses" panel that already records Claude, Codex, and Cursor responses now also records MiniMax — keyed `(provider: .minimax, endpoint: "coding_plan/remains")`. PII scrubbing and the no-headers-ever guarantee still apply. (`SlothyTerminal/Services/MinimaxUsageProvider.swift:41-49`)
- **`UsageModelsTests.testMinimaxFullRemainingReportsZeroPercent`** — pins the headline-case-on-a-fresh-week scenario: `usage_count == total_count` produces `used = 0`, `percentUsed = 0.0`, and `"Weekly used"` reads `"0 / 45000"`. Guards against any future "simplification" that re-inverts the semantics. (`SlothyTerminalTests/UsageModelsTests.swift:534-565`)
- **`UsageModelsTests.testMinimaxWeeklyUsedSubtractsRemaining`** — feeds weekly `44676 / 45000` (i.e. 324 used, 44676 remaining) and asserts the rendered metric is `"324 / 45000"`. Specifically guards the weekly subtraction path. (`SlothyTerminalTests/UsageModelsTests.swift:567-595`)
- **`UsageModelsTests.testClaudeOAuthParseEmitsAllPublishedPerModelWindows`** — feeds a real Anthropic response containing `seven_day_sonnet` + `seven_day_omelette` at `utilization: 0` and `seven_day_cowork` / `seven_day_opus` / `seven_day_oauth_apps` as JSON `null`, and asserts the two object channels surface at "0% used" while the three null channels stay absent. (`SlothyTerminalTests/UsageModelsTests.swift:418-462`)
- **`UsageModelsTests.testMinimaxParseHeadlineSnapshot` updated** to assert the inverted semantics: `used = 38`, `remaining = 4462`, `percentUsed ≈ 38 / 4500`, and `"Weekly used"` reads `"46 / 45000"`. (`SlothyTerminalTests/UsageModelsTests.swift:466-532`)

### Notes
- The Keychain entitlement bug was masked in earlier internal builds because OS-level provisioning sometimes lets `kSecUseDataProtectionKeychain` succeed without `application-identifier` if other implicit entitlements happen to be present. The reliable fix for an unsandboxed app is to omit the flag entirely — that selects the legacy file-based macOS keychain (`~/Library/Keychains/login.keychain-db`), which has no entitlement preconditions. If the app is ever sandboxed in the future, every removed `kSecUseDataProtectionKeychain: true` line will need to be restored alongside an appropriate keychain-access-group entitlement.
- `testMinimaxConnection` and `fetchMinimaxUsageViaService` are intentionally redundant: the first calls the HTTP client directly (so a green ✓ here means "API + key are fine"), the second runs the full Observable + service fetch chain (so a green ✓ here means "status bar should be visible"). A bug between the two layers shows up as ✓ / ✗ instead of being invisible.
- The popover height of 400 pt was chosen by eyeballing the Claude tab — currently the tallest case because of the new per-model 7d expansion. If a future provider adds substantially more rows, revisit before going below 400.

## [2026.3.11] - 2026-05-15

### Added
- **MiniMax usage stats as a fourth status-bar provider.** `UsageProvider.minimax` joins Claude, Codex, and Cursor in the bottom status bar, with the same compact bar + click-to-open popover. The headline percentage is read from the `MiniMax-M*` row of the coding-plan quota response (the canonical Coding Plan slot); `coding-plan-vlm` and `coding-plan-search` are skipped to avoid double-counting since the platform returns them as duplicate views of the same quota. If `MiniMax-M*` is absent, the row with the highest non-zero interval utilization wins so accounts without the coding plan still get a meaningful headline. Weekly usage and per-model non-coding rows (`speech-hd`, `image-01`, music/Hailuo) surface as `UsageMetric` entries in the popover. Closes #13. (`SlothyTerminal/Models/UsageModels.swift:9, 25, 31, 48`, `SlothyTerminal/Services/MinimaxUsageProvider.swift`, `SlothyTerminal/Services/UsageService.swift:236, 386-400, 428-429, 1793-1812`)
- **`MinimaxUsageProvider` service.** Calls `GET https://platform.minimax.io/v1/api/openplatform/coding_plan/remains` with `Authorization: Bearer <apiKey>`, 15s timeout. HTTP 401/403 maps to `UsageFetchError.tokenExpired` so the existing token-expired popover path picks it up; a `base_resp.status_code != 0` payload maps to `.parseError` with the upstream `status_msg` logged. The parse/build steps are `nonisolated static` so tests can drive them with fixture JSON without touching the network. (`SlothyTerminal/Services/MinimaxUsageProvider.swift`)
- **MiniMax Codable response models.** `MinimaxUsageResponse`, `MinimaxBaseResp`, `MinimaxModelRemains` mirror the upstream JSON exactly via `CodingKeys` for snake_case fields. `Int64` is used for ms-epoch timestamps and `remains_time` to avoid float precision drift. (`SlothyTerminal/Models/UsageModels.swift:231-281`)
- **Settings → Usage → MiniMax section.** New section directly after Cursor in `UsageSettingsView`. Status row reports connected / not-connected based on Keychain presence, a `SecureField` accepts the platform API key (obtained from `platform.minimax.io` → User Center → Interface Key), and Save / Clear Saved Key buttons drive `UsageKeychainStore.saveString(_, provider: .minimax, sourceKind: .apiKey)` and trigger `usageService.resolveAuthSources()` + `fetch(provider: .minimax)`. No env-var auto-detect — the Settings UI is the only source per design decision. (`SlothyTerminal/Views/SettingsView.swift:1109-1110, 1187-1234, 1329-1369`)
- **`Package.swift` registers `MinimaxUsageProvider.swift` in the `SlothyTerminalLib` sources list.** Per `AGENTS.md` § *Xcode project convention*, new non-UI Swift files in the SPM-covered core must be added manually or `swift test` will silently miss them. (`Package.swift:64`)
- **`UsageModelsTests.testMinimaxParseHeadlineSnapshot` and `testMinimaxParseRejectsErrorStatus`.** Fixture-based regression tests asserting (a) `MiniMax-M*` becomes the headline with the correct `percentUsed`, `used`, `limit`, `remaining`, and that `coding-plan-vlm` does not appear as a duplicate metric row, and (b) a `base_resp.status_code != 0` payload throws `UsageFetchError.parseError` rather than returning a malformed snapshot. (`SlothyTerminalTests/UsageModelsTests.swift:420-501`)
- **`UsageModelsTests.testMergedClaudeWindowReturnsRawPercentage` and `testMergedClaudeWindowZeroUtilization`.** Regression coverage for the Claude utilization scaling fix below. The first asserts that an Anthropic payload with `"utilization": 1` parses to `1.0` (1%) — not `100.0` as the previous "defensive" normalization would have produced — and that `"utilization": 7` parses to `7.0`. The second pins the zero case. (`SlothyTerminalTests/UsageModelsTests.swift:372-416`)

### Fixed
- **Claude OAuth utilization no longer inflated 100× for low values.** The Anthropic OAuth usage endpoint returns `utilization` as an already-scaled 0-100 percentage — a value of `1` means 1%, not 100%. A "defensive" `normalizeUtilization()` helper inside `mergedClaudeWindow()` was multiplying any value in `(0, 1]` by 100 on the theory that the API might also return fractions, which inflated a true 1% reading into 100% on the status bar. The helper has been removed and the raw `utilization` value flows through unchanged; verified against the full reading chain (`claudeWindowMetrics`'s `>= 90` warning thresholds, the `"\(Int(util))% used"` display format, and `percentUsed: sessionUtil / 100.0` in the snapshot builder) — all of these were already consistent with 0-100 semantics, so the bug was localized to the now-removed helper. Closes #12. (`SlothyTerminal/Services/UsageService.swift:720-768`)

### Changed
- **`claudeMetricCachePrefix` bumped from `"claudeUsageCache."` to `"claudeUsageCache.v2."`.** Pre-fix versions persisted cached `utilization` values that were inflated 100× by the now-removed normalize step. Those values would have lingered in `UserDefaults` for up to seven days (the `seven_day` window's `resetsAt` is the cache's only eviction trigger), during which `shouldPreferCachedClaudeWindow` could surface them over a correct fresh 0% reading. The prefix bump misses the old keys entirely on read, so they become inert immediately instead of being trusted. Old keys leak into UserDefaults until the user wipes app data, but they're never read again. (`SlothyTerminal/Services/UsageService.swift:787-797`)

### Notes
- The MiniMax API key is sent as `Authorization: Bearer <key>` against `platform.minimax.io`. Keys are stored in the macOS Keychain via `UsageKeychainStore` keyed under `provider: .minimax, sourceKind: .apiKey` — never in `~/.slothyterminal/config.json` or any plain file. The "Clear Saved Key" button deletes the Keychain entry and calls `usageService.clearProvider(.minimax)`, which also wipes the in-memory snapshot and refresh task. (`SlothyTerminal/Services/UsageService.swift:1793-1812`, `SlothyTerminal/Views/SettingsView.swift:1359-1369`)
- The MiniMax popover uses the standard `UsagePopoverView` rendering — no view changes were needed in `StatusBarUsageView.swift` because the popover and status bar both iterate `UsageProvider.statusBarProviders` and read snapshots through the existing `UsageService` API. Adding the enum case alone is enough to surface the new provider end-to-end.
- The `parseClaudeOAuthUsageResponse` end-to-end path is not yet covered by a regression test. The unit-level fix in `mergedClaudeWindow` is what was breaking, and the two new tests pin that behaviour, but a future hardening pass should add a snapshot-level test that asserts `percentUsed == 0.01` for `utilization: 1` to lock in the contract at the layer that feeds the UI.

## [2026.3.10] - 2026-05-08

### Added
- **Workspaces sidebar surfaces unread terminal activity at the workspace level.** Each `WorkspaceRowView` now renders an orange `BackgroundActivityIndicator` next to the workspace name when the workspace is *not* the active one and any tab inside it has `hasBackgroundActivity == true`. Previously the unread dot only existed at the tab level — once you switched to a different workspace, you couldn't tell at a glance which workspace had output waiting. The rollup is recomputed each render via the new `AppState.hasBackgroundActivity(in:)` helper, and the indicator reuses the same pulsing dot used on tab icons (with a workspace-specific tooltip "Workspace has unread terminal activity"). The active workspace never shows the dot — its tabs show their own per-tab indicators in the tab bar. (`SlothyTerminal/Views/WorkspacesSidebarView.swift:22-28, 152, 177-179`, `SlothyTerminal/App/AppState.swift:205-208`)
- **`AppState.hasBackgroundActivity(in:)`** — `O(tabs)` scan returning `true` if any tab whose `workspaceID` matches has its `hasBackgroundActivity` flag set. Lives next to `tabs(in:)` so the workspace-rollup helpers stay grouped. (`SlothyTerminal/App/AppState.swift:205-208`)
- **`BackgroundActivityIndicator` accepts a `help` override.** New stored property `var help: String = "New terminal activity"` so the workspace-level rollup can use a more specific tooltip ("Workspace has unread terminal activity") while the tab-level indicator keeps the original copy by default. (`SlothyTerminal/Views/TabBarView.swift:385-410`)
- **`AppStateWorkspaceTests` — workspace background-activity rollup coverage.** Two new tests: `workspaceBackgroundActivityRollup` asserts the rollup flips on after a tab in workspace A is marked active and stays off for workspace B, and that switching back to A clears it; `switchingWorkspaceClearsAllUnreadTabs` asserts every unread tab in the entered workspace gets acknowledged on switch — not just the one that becomes the active tab. (`SlothyTerminalTests/AppStateWorkspaceTests.swift:691-744`)
- **`TabActivityTests.terminalStaysBusyWithinIdleWindow`** — guards the new 2-second `terminalActivityIdleDelayNanoseconds`. Samples at 1.0s (still busy) and 2.4s (no longer busy). The shared `activityIdleWait` constant in the suite was bumped from 1.2s to 2.4s so the existing "becomes idle after the window" assertions still pass. (`SlothyTerminalTests/TabActivityTests.swift:8, 60-79`)

### Changed
- **Terminal "executing" idle window extended from 0.8s to 2.0s.** `Tab.terminalActivityIdleDelayNanoseconds` was 800 ms, which made the in-tab `ExecutingIndicator` flap on and off during ordinary command flows that emit output in short bursts (e.g. `git status` output, prompt redraws between sub-commands of a chained command). The dot would hide for a fraction of a second between bursts and re-appear, which read as visual noise rather than activity. Two seconds covers the common bursty-output cases without making the indicator feel stuck — a long-running build still keeps the indicator on continuously, and a one-shot command's indicator clears within a couple seconds of finishing. (`SlothyTerminal/Models/Tab.swift:40`)
- **Tab "executing" indicator keeps the agent accent colour while the tab is inactive.** Previously `TabItemView.tabLeadingIcon` painted `ExecutingIndicator` in `.gray` when the tab was neither active nor a split member — so a Claude tab running in the background showed a grey pulse instead of a Claude-coloured one, making it hard to tell at a glance which agent was working. The view now passes `tabAccentColor` unconditionally; the executing indicator now reads as "tab X is busy" instead of "*some* tab is busy" when scanning the tab bar. (`SlothyTerminal/Views/TabBarView.swift:335`)
- **Background-activity dot now coexists with the executing indicator.** Previously the orange unread dot was suppressed whenever `tab.isExecuting` was true (`tab.hasBackgroundActivity && !isActive && !tab.isExecuting`), reasoning that the executing pulse already told you the tab was busy. In practice this hid genuinely-unseen output: a tab finishes a command (executing → false, hasBackgroundActivity → true), the user doesn't switch to it, then the tab starts executing again and the unread dot disappears even though the user never saw the previous output. The guard is now just `tab.hasBackgroundActivity && !isActive`, so the dot persists across re-execution until the user actually switches to the tab. (`SlothyTerminal/Views/TabBarView.swift:356`)
- **Switching into a workspace acknowledges every unread tab in it, not just the active one.** `AppState.switchWorkspace(id:)` now iterates `tabs.filter { $0.workspaceID == id }` and calls `clearBackgroundActivity()` on each. The previous behaviour cleared only the tab that became `activeTab` after the switch — tabs you didn't focus retained their unread state forever, so the workspace-level rollup (above) would have shown the dot indefinitely. Acknowledging on entry matches how the per-tab dot already behaved at the tab level. (`SlothyTerminal/App/AppState.swift:232-236`)
- **Repository documentation split out of the monolithic `CLAUDE.md` / `README.md` into per-topic files under `docs/`.** New: `docs/architecture.md`, `docs/authentication.md`, `docs/domain.md`, `docs/gotchas.md`, `docs/interactions.md`, `docs/testing.md`. Existing `docs/RELEASE.md` renamed to `docs/release.md` for consistency, and `scripts/update-ghostty.sh` updated to reference the new path. `AGENTS.md` becomes the single entry point that points into `docs/`; `CLAUDE.md` is now a thin `@AGENTS.md` shim. (`AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/`, `scripts/update-ghostty.sh:201, 226`)
- **`prepare-macos-release` skill added under `.claude/skills/`.** Encodes the CHANGELOG / appcast voice and the placeholders-must-stay-intact contract that `./scripts/release.sh` enforces, so future releases can be drafted from `/prepare-macos-release VERSION` without reverse-engineering the format from prior entries. (`/.claude/skills/prepare-macos-release/SKILL.md`)

### Notes
- The rollup is recomputed every render — `WorkspacesSidebarView` calls `appState.hasBackgroundActivity(in: workspace.id)` per row inside `ForEach`, which is `O(workspaces × tabs)` total. Cheap at present scales (workspaces are typically < 10, tabs < 50) and avoids having to invalidate cached state from every tab-level activity write. If the workspace count grows by orders of magnitude, switch to a per-workspace counter on `AppState`.
- The 2-second idle threshold was chosen by feel against `git status`, `npm test`, and `claude` agent runs — not measured. If real-world use shows the indicator holding too long after one-shot commands, drop back to ~1.2s before going lower; below 1s the original flapping problem returns.

## [2026.3.9] - 2026-05-02

### Added
- **Finder Services menu entries: "New SlothyTerminal Tab Here" and "New SlothyTerminal Window Here".** Right-clicking a folder in Finder → Services now offers two SlothyTerminal entries that launch (or focus) the app and open a `.terminal` session rooted at the selected folder. "New Tab Here" appends a `.terminal` tab to the currently active workspace via the existing `AppState.createTab(agent:directory:)` path. "New Window Here" creates a brand-new workspace rooted at the folder and opens a `.terminal` tab inside it — bypassing the dedupe logic in `resolveWorkspaceID` so a fresh workspace is always created. Items only appear when a folder is selected (`NSSendTypes = public.folder`, `NSRequiredContext.NSTextContent = FilePath`); multi-selection collapses to the first folder in pasteboard order, matching Ghostty. Debug builds suffix the titles with ` [DEBUG]` via `#ifdef DEBUG_BUILD` in `Info.plist` (preprocessed because `INFOPLIST_PREPROCESS = YES`). (`SlothyTerminal/Info.plist:23-83`, `SlothyTerminal/Services/FinderServicesProvider.swift`, `SlothyTerminal/App/AppState.swift:349-361`, `docs/plans/context-menu.md`)
- **`FinderServiceRequestQueue` — cold-launch buffer for Services callbacks.** macOS routes Services invocations through `NSApp.servicesProvider` immediately after launching the app, so on cold launch the callback can fire before SwiftUI's scene `.onAppear` has run. The queue buffers `FinderServiceRequest` values (`.newTab(folder:)` / `.newWindow(folder:)`) under an `NSLock` and flushes them onto the main actor when `SlothyTerminalApp.onAppear` attaches the sink. First attach wins — subsequent `.onAppear` re-fires (e.g. window restoration) are no-ops, so already-drained buffers are not re-driven. Provider lifecycle: `AppDelegate.applicationWillFinishLaunching` instantiates `FinderServicesProvider`, retains it on `self`, assigns `NSApp.servicesProvider`, and calls `NSUpdateDynamicServices()` — chosen over `didFinishLaunching` so the provider is registered before any queued service invocation runs. (`SlothyTerminal/Services/FinderServiceRequestQueue.swift`, `SlothyTerminal/App/AppDelegate.swift:11-22`, `SlothyTerminal/App/SlothyTerminalApp.swift:16-27`)
- **`AppState.createWorkspaceAndTerminalTab(directory:)`** — creates a fresh workspace from the directory and a `.terminal` tab inside it, bypassing `resolveWorkspaceID`'s dedupe so the Finder "New Window Here" service never reuses or removes a workspace that happens to share the same root. (`SlothyTerminal/App/AppState.swift:349-361`)
- **App UI font picker (Appearance → "App Font").** New `AppConfig.appFont: AppFont` with two cases — `.system` (default) and `.jetBrainsMono` — independent of `terminalFontName`. Settings exposes a segmented picker plus a live preview row that renders in the picked font. JetBrains Mono Regular and Bold ship inside the bundle; the family name `"JetBrains Mono"` resolves both faces so SwiftUI's `.bold()` modifier picks up the bundled bold variant. (`SlothyTerminal/Models/AppConfig.swift:46-49, 263-292`, `SlothyTerminal/Views/SettingsView.swift:245-269`)
- **Bundled fonts: JetBrains Mono Regular + Bold (TTF, OFL-licensed).** Files live at `SlothyTerminal/Resources/Fonts/` and ship in `Contents/Resources/` (flattened by `PBXFileSystemSynchronizedRootGroup`). `Info.plist` registers them via `ATSApplicationFontsPath = "."` — the value is `"."` (Resources root), **not** `"Fonts"`, because the Xcode synchronized group flattens the folder structure at build time; setting it to `"Fonts"` makes the registration silently fail and the picker falls back to system. A DEBUG-only `AppDelegate.assertBundledFontsRegistered()` calls `NSFont(name:size:)` for each required PostScript name and `assertionFailure`s on miss, so a regression here surfaces in development instead of shipping silently. (`SlothyTerminal/Info.plist:5-15`, `SlothyTerminal/App/AppDelegate.swift:26-39`, `SlothyTerminal/Resources/Fonts/JetBrainsMono-Regular.ttf`, `SlothyTerminal/Resources/Fonts/JetBrainsMono-Bold.ttf`, `SlothyTerminal/Resources/Fonts/OFL.txt`)
- **`View.appFont(...)` modifier family.** Three overloads in `AppFontModifier.swift`: `.appFont(_ font: AppFont)` sets the environment default font (returns the same view type unconditionally so flipping `AppFont` at runtime does not destroy `@State` in subtrees like `SettingsView`'s selected section); `.appFont(size:weight:design:)` is a drop-in for `.font(.system(size:weight:design:))`; `.appFont(_ style: Font.TextStyle)` maps semantic styles (`.body`, `.caption`, …) to `Font.custom(_:size:relativeTo:)` so Dynamic Type still scales while the bundled font is active. Both runtime modifiers read `ConfigManager.shared.config.appFont` (an `@Observable`) so views re-render when the picker changes. The sized variant intentionally does **not** scale with Dynamic Type so layout-critical chrome stays predictable. (`SlothyTerminal/Views/AppFontModifier.swift`)
- **`AppButton`** — plain-text wrapper around SwiftUI `Button` whose label is an explicit `Text(...).appFont(size:weight:)`. Necessary because AppKit-backed button styles (`.borderedProminent`, etc.) ignore the SwiftUI environment font for string-literal labels — they pull from `NSFont.systemFont(ofSize:)` directly. The wrapper composes normally with caller-applied `.buttonStyle`, `.disabled`, and `.keyboardShortcut`. (`SlothyTerminal/Views/AppButton.swift`)
- **`AppConfigTests`** — unit coverage for `AppFont` Codable round-trip, default value, and decoder fallback when the key is missing from disk. (`SlothyTerminalTests/AppConfigTests.swift`)
- **`AppStateWorkspaceTests`** — covers `createWorkspaceAndTerminalTab` always producing a fresh workspace even when an existing workspace already roots at the same directory. (`SlothyTerminalTests/AppStateWorkspaceTests.swift`)
- **`FinderServiceRequestQueueTests`** — unit coverage for queue buffering before attach, draining on attach, the "first attach wins" guard, and the `resetForTesting` seam. (`SlothyTerminalTests/FinderServiceRequestQueueTests.swift`)

### Changed
- **App-wide migration of `.font(...)` call sites to `.appFont(...)`.** Roughly 30 views updated to route through the new modifier family so the user's font choice actually takes effect. Touched: `AboutView`, `AutomationSidebarView`, `CloseButton`, `FolderSelectorModal`, `GitClientView`, `MainView`, `MakeCommitComposerView`, `MakeCommitDiffContentView`, `MakeCommitSidebarView`, `MakeCommitView`, `ModelPicker`, `PromptsSidebarView`, `RevisionGraphView`, `SettingsView`, `SidebarContainerView`, `SidebarView`, `StartSessionContentView`, `StartupPageView`, `StatusBarUsageView`, `TabBarView`, `TerminalContainerView`, `WorkspacesSidebarView`. Native window chrome (title bar, menu bar) and the Ghostty terminal surface are unaffected — they use system / terminal fonts respectively, as documented in the picker's caption.
- **`SlothyTerminalApp` scene applies `.appFont(configManager.config.appFont)` to `MainView`, `SettingsView`, and `AboutView`.** Required because each `WindowGroup` / `Window` is its own SwiftUI environment scope; without applying the modifier per scene the picker only affected the main window. (`SlothyTerminal/App/SlothyTerminalApp.swift:14-15, 140, 146`)
- **`Package.swift` `SlothyTerminalLib` sources** add `Services/FinderServiceRequestQueue.swift` (covered by `swift build` / `swift test`) and `excludes` add `Services/FinderServicesProvider.swift` (AppKit / `NSPasteboard` / `NSApp` — Xcode-only). (`Package.swift:32-43`)

### Notes
- `AppButton` is intentionally narrow: only the title is themed. Bordered SwiftUI buttons that already use a closure label (`Button { … } label: { Text(...).appFont(...) }`) don't need the wrapper — it exists specifically for the string-literal initializer that loses the environment font.
- The DEBUG suffix on Services menu titles (`[DEBUG]`) ships as a separate user-visible label, not via a separate plist — `INFOPLIST_PREPROCESS = YES` runs the file through the C preprocessor at build time, so the `#ifdef DEBUG_BUILD` block resolves to one or the other in the built bundle. Verify with `plutil -p Contents/Info.plist | grep -A1 NSMenuItem` against the `.app` bundle, not the source plist.
- `NSPortName` is `"SlothyTerminal"` for both Debug and Release. It must equal the built `CFBundleName` (driven by the Xcode `PRODUCT_NAME` / `INFOPLIST_KEY_CFBundleName` build settings, **not** by the runtime `BuildConfig.appName` which only governs in-app strings). Mismatch causes macOS to silently drop Services invocations.
- Pasteboard parsing uses `readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])` and filters by `FileManager.fileExists(atPath:isDirectory:)`. Non-folder entries in mixed selections are filtered out before picking the first folder; an empty result writes `"No folder selected."` into the `error` out-pointer.

## [2026.3.8] - 2026-05-01

### Changed
- **Cursor usage popover replaces token / event / error counts with a per-model spend breakdown.** The "Included value / Tokens (in / out) / Tokens (cache) / Events / Errors (not charged)" rows were derived sums that didn't match what cursor.com shows on the dashboard, and "Errors (not charged)" wasn't actionable. The popover now surfaces the dashboard's own `planUsage.apiPercentUsed` / `autoPercentUsed` directly (ground truth from Cursor) plus a "Spend ($X / $Y (P%))" row, then a new "Usage by model" section listing the top 5 chargeable models for the current period, ordered by total spend descending. Per-row identity is keyed by `timestamp + model` (`UsageEventDisplay.id`) so refetches don't churn SwiftUI's `ForEach` diff. (`SlothyTerminal/Services/CursorUsageProvider.swift:531-600`, `SlothyTerminal/Models/UsageModels.swift:137-195`, `SlothyTerminal/Views/StatusBarUsageView.swift:307-336`)
- **Cursor `parseCurrentPeriod` reads the new `planUsage`-nested shape.** Cursor's `get-current-period-usage` response moved its primary plan totals under a `planUsage` object: `totalSpend`, `limit`, `includedSpend` (all in cents — divided by 100 to get dollars), `apiPercentUsed` / `autoPercentUsed` (already percentages — `5.318` is 5.32%, not 531.8%), and a top-level `billingCycleEnd` (epoch ms). Legacy flat keys (`totalCents`, `includedCreditCents`, `hardLimitCents`, bare `totalCost` / `totalSpend`) are still tried as a fallback so accounts whose dashboard endpoint hasn't migrated keep working. (`SlothyTerminal/Services/CursorUsageProvider.swift:419-465`)
- **`UsageSnapshot.percentUsed` is now a 0-1 fraction for Cursor, matching the contract the rest of the app expects.** `StatusBarUsageBars.usageBarCapsule(percent:)` and the popover progress bar both treat `percentUsed` as 0-1 and multiply by 100 only for the percentage label — the previous `buildSnapshot` returned 0-100 for Cursor, which would 100× over-fill the capsule and render labels like "5318%" as soon as any spend was reported. (`SlothyTerminal/Services/CursorUsageProvider.swift:560-565`)
- **Status-bar usage strip shows provider names instead of SF Symbols.** The leading `brain.head.profile` / `curlybraces` / `cursorarrow.rays` glyphs are replaced with each provider's `displayName` ("Claude", "Codex", "Cursor") at `.system(size: 10, weight: .medium)`. SF Symbols still drive transient state (loading spinner, `exclamationmark.triangle.fill`, `key.slash`, `minus.circle`), so the row still communicates that information without a label. (`SlothyTerminal/Views/StatusBarUsageView.swift:69-72`)
- **Each bar is now individually tappable.** Tapping a single provider's bar opens the popover with that provider's tab pre-selected; the previous behaviour required a tap on the strip background and then a manual segmented-picker click to switch tabs. `selectedProvider` was lifted out of `UsagePopoverView` and into `StatusBarUsageBars` (passed as `@Binding`) so per-bar gestures can set it before the popover-isPresented binding flips. The strip-level tap still toggles the popover. (`SlothyTerminal/Views/StatusBarUsageView.swift:13, 33-40, 57-60, 145`)
- **Status-bar strip gains a hover highlight.** A subtle rounded-rectangle fill (`Color.primary.opacity(0.08)`, corner radius 4) appears on hover so the strip reads as a clickable affordance. (`SlothyTerminal/Views/StatusBarUsageView.swift:42-51`)
- **"Latest JSON Responses" panel ships in Release builds.** The Settings → Usage → "Latest JSON Responses" diagnostic surface (and `ProviderResponseStore.record` capture at all eight call sites) was previously gated behind `#if DEBUG`. The PII guarantees that justified shipping it are unchanged — auth headers (`Cookie`, `Authorization`) are never recorded, email-shaped substrings are scrubbed via `scrubPII` before storage, and entries live only in-memory for the lifetime of the process. Making the panel Release-visible lets users include the actual JSON a provider returned in bug reports without rebuilding from source. (`SlothyTerminal/Services/ProviderResponseStore.swift:1-15`, `SlothyTerminal/Services/UsageService.swift:701-705, 1180-1184, 1282-1286, 1467-1471, 1700-1704`, `SlothyTerminal/Services/CursorUsageProvider.swift:158-163, 217-225, 233-237`, `SlothyTerminal/Views/SettingsView.swift:1073-1099, 1257-1456`)
- **Popover content area uses asymmetric padding** (12pt leading, 12pt trailing, 12pt vertical — was 12pt all sides) so the AppKit overlay scrollbar no longer clips trailing numeric values in long metric rows. (`SlothyTerminal/Views/StatusBarUsageView.swift:178-181`)

### Added
- **`UsageEventDisplay`** — provider-agnostic value type carrying `model`, `dollars`, and `timestamp`, with a derived `id` ("`<epoch>-<model>`") that stays stable across refetches so SwiftUI's `ForEach` doesn't recreate rows on every poll. (`SlothyTerminal/Models/UsageModels.swift:137-152`)
- **`UsageSnapshot.events: [UsageEventDisplay]`** with a default value of `[]` in the new explicit initializer — feeds the popover's "Usage by model" section. Existing Claude / Codex snapshot construction is unchanged because the parameter has a default. (`SlothyTerminal/Models/UsageModels.swift:166, 174-195`)
- **`CursorUsageProvider.groupEventsByModel(_:limit:)`** — groups events by `model`, sums `chargedDollars` (and tracks the most-recent timestamp per model), returns the top `limit` rows ordered by spend descending. Marked `nonisolated` and `internal` so the unit tests can exercise it without going through the HTTP path. Backed by `recentEventsLimit = 5`. (`SlothyTerminal/Services/CursorUsageProvider.swift:519-520, 644-674`)
- **`UsageEvent.chargedDollars` and `.timestamp` fields** — derived from each event's `chargedCents` (cents → dollars) and `timestamp` (epoch-ms, parsed via the new `parseEpochMSField` helper that tolerates the API's mixed string/number serialization). Authoritative source for the per-event dollar amount in the breakdown — `usageBasedCosts` is often `"-"` on Ultra plans. (`SlothyTerminal/Services/CursorUsageProvider.swift:357-364, 401-431`)
- **`CurrentPeriodTotals` gains `apiPercentUsed`, `autoPercentUsed`, `totalSpendDollars`, `limitDollars`, `billingCycleEnd`.** All five come from the new `planUsage`-nested response shape. The first two are stored as percentages (0-100); the dollar fields are converted from cents at parse time; `billingCycleEnd` is an epoch-ms timestamp converted to `Date`. (`SlothyTerminal/Services/CursorUsageProvider.swift:373-385`)
- **`formatPeriodReset(cycleEnd:periodStart:)`** prefers the API-provided `billingCycleEnd` when present and falls back to the previous "first of next month, UTC" derivation only when the dashboard endpoint omits it. (`SlothyTerminal/Services/CursorUsageProvider.swift:676-700`)
- **`CursorUsageProviderTests` (~330 lines)** — unit-test coverage for the parsers and snapshot builder: `planUsage` shape, legacy flat-shape fallback, `billingCycleEnd` decoding, `parseEventsPage`, `groupEventsByModel` (ordering, top-N truncation, multi-event aggregation), and `buildSnapshot` shape (metric labels, `percentUsed` normalization to 0-1, recent-events surfacing). (`SlothyTerminalTests/CursorUsageProviderTests.swift`)

### Removed
- **Cursor popover rows: "Included value", "Tokens (in / out)", "Tokens (cache)", "Events", "Errors (not charged)".** Replaced by the dashboard-aligned "API usage" / "Auto model usage" / "Spend" rows and the "Usage by model" section. The previous values were derived from the event feed alone and didn't match cursor.com because the feed only includes chargeable events while the dashboard aggregates over more. (`SlothyTerminal/Services/CursorUsageProvider.swift:531-588`)
- **`#if DEBUG` gates around `ProviderResponseStore.record` capture and the Settings panel** — no remaining DEBUG-only paths in the response-capture flow.

### Fixed
- **`UsageModelsTests.testUsageStatusBarProviders` aligned with the actual `statusBarProviders` array.** The test still asserted `[.claude, .codex]` after `.cursor` was added in 2026.3.4, so `swift test` had been failing locally on `develop` since that release. (`SlothyTerminalTests/UsageModelsTests.swift:29`)

### Notes
- The "Recent usage" / "Usage by model" section is currently Cursor-only (Claude and Codex don't expose a per-event feed in the same shape). The `events` field is on the snapshot for any provider, so adding it to other providers later is just a matter of populating that field from their parsers.
- `chargedDollars` is the authoritative per-event dollar source going forward; `cost` (legacy `usageBasedCosts`) is retained on `UsageEvent` because the field still distinguishes paid vs. `INCLUDED_*` rows in the kind-based summation, even when its raw value is `"-"`.

## [2026.3.7] - 2026-05-01

### Changed
- **Cursor usage now reads from the dashboard backend instead of the legacy `cursor.com/api/usage` endpoint.** The old endpoint reports zeros for accounts on Cursor's token-based billing model (Pro / Pro+ / Ultra), so the popover was effectively dead for the majority of paying users. `CursorUsageProvider.fetchUsage` now POSTs to the same two endpoints the web dashboard uses: `https://cursor.com/api/dashboard/get-filtered-usage-events` (paginated per-event detail — model, kind, `tokenUsage`, `usageBasedCosts`) and `https://cursor.com/api/dashboard/get-current-period-usage` (aggregated $ spent vs. plan limit). Both authenticate with the same `WorkosCursorSessionToken` cookie used by the website. Pagination is hard-capped at `eventsPageCap = 50` pages × `eventsPageSize = 100` events to bound the loop; the events fetch terminates early when a page returns < `eventsPageSize` rows. Per-page response bodies are captured into `ProviderResponseStore` (DEBUG only). (`SlothyTerminal/Services/CursorUsageProvider.swift:18-28`)
- **Cookie components are now percent-encoded (RFC 3986 unreserved set).** The previous implementation rejected any JWT or `sub` claim containing characters outside `[A-Za-z0-9._-]` via `isHeaderSafe`, which broke OAuth users whose `sub` claim looks like `google-oauth2|12345` (the `|` failed validation, `fetchUsage` threw `.invalidCredentials`). `buildSessionCookie` now percent-encodes both the userID and JWT halves and joins them with `%3A%3A` — the Cursor server URL-decodes before parsing, so the original colon-separated form round-trips correctly. (`SlothyTerminal/Services/CursorUsageProvider.swift:103-110`)
- **Cursor snapshot now reports dollars, tokens, events, and errors** instead of monthly request counts. Metrics surfaced in the popover: `Spent (this period)` (with plan limit when available), `Included value` (sum of `INCLUDED_IN_PRO` / `INCLUDED_IN_ULTRA` would-be costs), `Tokens (in / out)`, `Tokens (cache)` (read + write), `Events` (total for the period), `Errors (not charged)` (count of `ERRORED_*` events), and `Resets` (calculated as start-of-current-month UTC + 1 month). Falls back to event-summed `spentUsageBased` if `get-current-period-usage` 4xxs. The `usageBasedCosts` field is parsed defensively — the API returns it as a `"$1.23"` string, raw number, dict with `cost`/`totalCost`, or array, depending on the row. (`SlothyTerminal/Services/CursorUsageProvider.swift:611-757`)
- **Cursor JWT decode and state-DB read paths gained verbose diagnostic logging.** `decodeUserID` now logs the specific failure step (segment count, base64 decode, JSON parse, missing `sub`) with a `redact()`-ed token sample (length + first/last 4 chars) so format changes by Cursor are debuggable from `Logs.app` without leaking the full token. The state-DB reader logs the raw token's segment count and a JWT-shape sanity check. (`SlothyTerminal/Services/CursorUsageProvider.swift:296-330`, `:679-703`)

### Added
- **Logs settings tab** — new `SettingsSection.logs` ("Logs" / `doc.text.magnifyingglass` SF Symbol) backed by `LogReader`, which queries `OSLogStore(scope: .currentProcessIdentifier)` filtered by `subsystem == Bundle.main.bundleIdentifier`. Rolling 2-hour window anchored at "now" on every fetch; refreshes every 2 seconds via a `.task(id: isPaused)` polling loop, with the `LogReader.fetch` call hopped off the main actor via `Task.detached(priority: .userInitiated)`. UI controls: minimum-level picker (Debug / Info / Notice / Error / Fault, default `.error`), category filter, Pause / Resume, Refresh, Copy All (ISO8601 + level + category + message). Categories list auto-derives from currently-loaded entries plus "All". Statusline footer uses `TimelineView(.periodic(... by: 1.0))` so the "Refreshed Ns ago" counter updates without re-fetching. (`SlothyTerminal/Services/LogReader.swift`, `SlothyTerminal/Views/SettingsView.swift:1593-1843`, `SlothyTerminal/Models/SettingsSection.swift`)
- **`ProviderResponseStore` (DEBUG-only)** — `@Observable @MainActor` singleton holding the most recent raw HTTP response per `(provider, endpoint)` pair, surfaced in Settings → Usage → "Latest JSON Responses" with status badge, host+path, body preview (expand/collapse), Copy JSON, Refetch, and byte count. Built to make API-shape investigation possible without re-instrumenting code or attaching a proxy. Capture is gated behind `#if DEBUG` at all six call sites in `UsageService` (Anthropic OAuth usage, admin orgs, browser orgs; OpenAI wham/usage, openai-org) and the two new Cursor call sites — the entire feature is inert in Release builds. (`SlothyTerminal/Services/ProviderResponseStore.swift`, `SlothyTerminal/Views/SettingsView.swift:1268-1427`)
- `LogReader.Entry` value type (id / date / level / category / message) and `LogReader.Level` (Comparable, ordered ascending by severity so `>=` works for "minimum level" filtering). Maps `OSLogEntryLog.Level.undefined` → `.notice` so unfamiliar future cases surface visibly rather than getting silently dropped.

### Security
- **`ProviderResponseStore.scrubPII`** — email-shaped substrings (`[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}`) in captured response bodies are replaced with `[redacted-email]` before storage. Several provider responses (Anthropic admin orgs, OpenAI org, ChatGPT wham/usage) include the caller's account email; the developer reviewing JSON shape doesn't need the address and shouldn't see it in screenshots/logs by default.
- **No request headers are ever recorded.** `ProviderResponseStore.record` accepts only the URL, status code, and response body — `Cookie` and `Authorization` headers from outbound requests are never stored, even in DEBUG.
- **`upsert` race guard.** Cursor's paginated fetch fires `record(...)` once per page, each scheduling an unstructured `Task { @MainActor in upsert(...) }`. Swift Concurrency does not guarantee FIFO ordering of those tasks on the target actor, so `upsert` rejects writes whose `fetchedAt` is not strictly newer than the existing entry — without this, an older page could overwrite a newer one when reordered.

### Removed
- **`CursorUsageProvider.isHeaderSafe(_:)`** — the previous header-injection guard against CR/LF/null-byte injection in the `Cookie` header. Superseded by `percentEncodeCookieComponent` (which encodes those characters along with everything else outside the RFC 3986 unreserved set), so the value is now safe by construction.
- **`CursorUsageProvider.parseUsageResponse(...)` and `failureSnapshot(...)`** — dead code paths for the legacy flat-/`modelUsages`-shaped response. The new pipeline uses `parseEventsPage` + `parseCurrentPeriod` + `buildSnapshot`.

### Notes
- `Package.swift` updated to include `Services/LogReader.swift` and `Services/ProviderResponseStore.swift` in the `SlothyTerminalLib` `sources:` list, so both new files are covered by `swift build` / `swift test`.
- `OSLogStore(scope: .currentProcessIdentifier)` only sees entries emitted by the current process — entries from prior runs are not visible. This is intentional: the tab is a live debugging aid, not a forensic log archive. To export historical logs, use `Console.app` or `log show --predicate 'subsystem == "<bundle id>"' --last 1d` from a Terminal session.

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
