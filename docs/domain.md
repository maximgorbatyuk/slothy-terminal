# Domain

The product surface is a tabbed window that hosts terminal sessions. The domain shapes the user interacts with — directly or indirectly — are documented here. For implementation see the directory linked next to each shape.

## Workspace (`Models/Workspace.swift`)

A named container that groups tabs under a single root directory.

- A workspace has an `id`, `name`, `rootDirectory`, and an optional `splitState`.
- `splitState` is non-nil when the workspace is in side-by-side mode (`Models/WorkspaceSplitState.swift`).
- An empty workspace (no tabs) may be retargeted at a different directory rather than discarded — picked up automatically by `AppState`'s "create workspace and tab" flow.
- Workspaces are persisted inside `AppConfig` and decoded resiliently: unknown keys must not crash older files.

## Tab (`Models/Tab.swift`)

A single session inside a workspace. Three shapes exist (`TabMode`: `.terminal` / `.git` / `.editor`):

- **Terminal mode** — runs an external process (claude / opencode / shell) inside a libghostty surface.
- **Git mode** — pure SwiftUI Git client, no PTY, no agent. Has no `agentType`.
- **Editor mode** — pure SwiftUI file editor (STTextView + tree-sitter), no PTY, no agent. Has no `agentType`. Carries a `fileURL` (required) and an `isDirty` flag.

Invariants:

- A non-terminal tab (`.git` / `.editor`) must not have an `agentType` (asserted in `init`).
- An `.editor` tab must carry a non-nil `fileURL` (asserted in `init`).
- For `.editor` tabs the displayed `title` is derived from `fileURL.lastPathComponent`; writes to `Tab.title` are an assertion-no-op so that Save As (which mutates `fileURL`) keeps the title in sync automatically.
- Only `.terminal` tabs with `agentType == .terminal` show the last submitted command in the tab label. Claude/OpenCode tabs use the agent's display name. Editor tabs show the file name, with a leading `● ` while dirty.
- `isTerminalBusy` is set on terminal activity and auto-cleared after a short idle window. `hasBackgroundActivity` flags unseen output on a non-active tab and is cleared on activation. `.git` and `.editor` tabs always report `isExecuting == false`.

Tab title and label rules live in `tabName` / `displayTitle`. The full token-aware command-label parser (`commandLabel(from:)`) handles `env`, `sudo`, `command`, env assignments, quoting, and `--` terminators.

## AgentType (`Models/AgentType.swift`)

Three cases: `terminal`, `claude`, `opencode`. Each carries its own SF Symbol icon and accent colour. Two behavioural flags drive launch-time decisions:

- `supportsInitialPrompt` — Claude and OpenCode accept an initial prompt; plain terminal does not.
- `needsShellHost` — Claude and OpenCode are spawned under a shell host so the tab survives the agent exiting (otherwise the PTY would have no leader and the surface would freeze).

## AIAgent (`Agents/AIAgent.swift`)

Protocol the three agent structs implement. Each agent supplies:

- `command` — resolved executable path. Claude prefers a Mach-O binary over a Node.js wrapper script and honours `CLAUDE_PATH`. OpenCode honours `OPENCODE_PATH` and otherwise falls back to PATH lookup. Terminal uses `$SHELL` (defaulting to `/bin/zsh`).
- `defaultArgs` and `argsWithPrompt(_:)` — argument construction. The default `argsWithPrompt` uses `--` to terminate flag parsing before the prompt text. OpenCode overrides this to use `--prompt` for its TUI.
- `environmentVariables` — minimum is `TERM=xterm-256color` + `COLORTERM=truecolor`. `TerminalView.makeLaunchEnvironment()` adds the rest of the required `TERM_PROGRAM*` vars at spawn time.
- `isAvailable()` — checks for the binary on disk; drives the startup-page UI's "install required" warnings.

The factory (`AgentFactory`) is the only place that constructs concrete agents.

## Tab launch flow

1. User picks an agent + directory on the startup page (or via Finder Services / a saved prompt / `Cmd+T`).
2. `AppState` constructs a `Tab` and appends it to the active workspace.
3. `TerminalView` builds the launch environment, asks the agent for its command and args, and creates a libghostty surface configured for that PTY.
4. The surface registers itself with `TerminalSurfaceRegistry` so the injection orchestrator can find it by tab id.
5. On tab close, the surface is destroyed and the registry entry removed.

## Editor tab (`Models/Tab.swift` mode `.editor`, `Views/Editor/`, `Services/FileEditorService.swift`)

The editor is a separate `TabMode` with no PTY, no agent, and no Ghostty surface. It is opened by:

- Double-clicking a file in the *Files* sidebar (`SidebarView.FileItemRow` → `AppState.openFileInEditor`).
- File menu → *Open…* once a file is picked (where applicable).

Folder rows in the *Files* sidebar use the same double-click gesture to toggle expansion; they never open editor tabs.

Open flow:

1. `AppState.openFileInEditor(_:)` canonicalizes the URL via `Self.canonicalFileURL(_:)` — `resolvingSymlinksInPath().standardizedFileURL`. This is the equality key for editor tabs across symlinks, `/tmp` vs `/private/tmp`, and trailing-slash variants.
2. If any existing tab in any workspace already edits the canonical URL, that tab is focused (switching workspaces if needed) instead of opening a duplicate.
3. Otherwise a new `.editor` tab is appended to the active workspace, with `workingDirectory` set to the workspace root (not the file's parent), so Cmd+T and git-branch context keep targeting the workspace the user opened.

Read / write:

- `FileEditorService.load(_:)` reads with a single `FileHandle` — size, binary sniff (NUL bytes in the first 8 KB), and content all come from the same descriptor to close the TOCTOU window. Files over 10 MB are refused (`EditorError.tooLarge`); binary content is refused (`EditorError.binaryFile`); the loader walks `utf8 → windowsCP1252 → macOSRoman → isoLatin1` and falls back through them in order.
- `FileEditorService.save(_:to:encoding:)` resolves symlinks before writing (so editing a symlinked dotfile keeps the link intact) and uses an atomic write.

Dirty-close lifecycle:

- `Tab.isDirty` is the source of truth. The editor view toggles it on every text change.
- `AppState.closeTab(id:)` does not close a dirty editor tab directly. It snapshots the current `(workspaceID, tabID)` into `dirtyEditorCloseReturnContext`, switches to the dirty tab if needed, and sets `tabPendingDirtyEditorClose` — which `EditorTabView` observes to present the Save / Don't Save / Cancel alert.
- *Save* writes the buffer and, if the post-save state is still clean, completes the close. If the user typed during the save, the close is cancelled and the dirty marker stays.
- *Don't Save* clears `isDirty` and finishes the close (`discardAndCloseDirtyEditor`).
- *Cancel* drops the pending-close request and restores the snapshotted `(workspaceID, tabID)` so the user is returned to where they were before the alert preempted them (`cancelDirtyEditorClose`).
- `performCloseTab` precondition-traps if a dirty editor tab reaches it without going through the sheet — preventing silent data loss.

Save / Save As / Revert are surfaced to the global File menu through `FocusedValues` (`editorSave`, `editorSaveAs`, `editorRevert`), bound to Cmd+S / Cmd+Shift+S. The menu items render unconditionally (see `docs/gotchas.md`).

## Injection (`Injection/`)

Programmatic input to a running terminal surface — used by saved prompts, the "open in tab" flow, and Finder Services.

- An `InjectionRequest` carries an `InjectionTarget` (active tab / specific id / filter by agent+mode), an `InjectionPayload` (text, command, paste, control signal, key event), and an optional timeout.
- `InjectionOrchestrator` keeps **one FIFO queue per tab id**. Requests are accepted, queued, then drained synchronously per tab.
- Status escalation is **"worst wins"**: once a request is `failed` / `timeout` / `cancelled`, a later `completed` from another tab cannot overwrite it.
- A bounded history (`maxHistorySize` in the orchestrator) is kept for status lookups; oldest completed requests are evicted when the cap is hit.
- Default per-entry timeout is `defaultTimeout` (declared in the orchestrator).

## Saved prompts (`Models/SavedPrompt.swift`)

Reusable prompt text + optional tags, attached to a launch. Persisted inside `AppConfig`. When a tab is created with `initialPrompt`, the agent's `argsWithPrompt(_:)` builds the launch arguments. Tag persistence is backwards-compatible: older configs that lack the tag field still decode.

## Usage stats (`Models/UsageModels.swift`, `Services/UsageService.swift`)

Per-provider snapshot of plan limits and token spend. Providers are `claude`, `codex`, `opencode`, `cursor`. Each snapshot has a source kind (`apiKey`, `cliOAuth`, `browser`, `experimental`). Auth resolution and credential storage are documented in `docs/authentication.md`.

## Stable invariants

- A `Tab` always belongs to exactly one `Workspace` (`workspaceID`).
- `agentType == nil` ⇒ `mode ∈ {.git, .editor}`. The reverse is asserted in `Tab.init`.
- An `.editor` tab always carries a non-nil `fileURL` (asserted in `Tab.init`).
- A dirty `.editor` tab cannot reach `AppState.performCloseTab`. The Save / Don't Save / Cancel sheet flow is the only legal close path; bypassing it precondition-traps.
- Bundled font registration must succeed at launch — `AppDelegate.assertBundledFontsRegistered()` will fail loud if `ATSApplicationFontsPath` is misconfigured.
- A terminal surface is registered with `TerminalSurfaceRegistry` for the lifetime of its tab; injection that arrives before registration sees an empty queue and fails fast with `"No surface registered"`.
