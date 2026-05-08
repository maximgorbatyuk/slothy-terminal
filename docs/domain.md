# Domain

The product surface is a tabbed window that hosts terminal sessions. The domain shapes the user interacts with — directly or indirectly — are documented here. For implementation see the directory linked next to each shape.

## Workspace (`Models/Workspace.swift`)

A named container that groups tabs under a single root directory.

- A workspace has an `id`, `name`, `rootDirectory`, and an optional `splitState`.
- `splitState` is non-nil when the workspace is in side-by-side mode (`Models/WorkspaceSplitState.swift`).
- An empty workspace (no tabs) may be retargeted at a different directory rather than discarded — picked up automatically by `AppState`'s "create workspace and tab" flow.
- Workspaces are persisted inside `AppConfig` and decoded resiliently: unknown keys must not crash older files.

## Tab (`Models/Tab.swift`)

A single session inside a workspace. Two shapes exist:

- **Terminal mode** — runs an external process (claude / opencode / shell) inside a libghostty surface.
- **Git mode** — pure SwiftUI Git client, no PTY, no agent. Has no `agentType`.

Invariants:

- A `.git` tab must not have an `agentType` (asserted in `init`).
- Only `.terminal` tabs with `agentType == .terminal` show the last submitted command in the tab label. Claude/OpenCode tabs use the agent's display name.
- `isTerminalBusy` is set on terminal activity and auto-cleared after a short idle window. `hasBackgroundActivity` flags unseen output on a non-active tab and is cleared on activation.

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
- `agentType == nil` ⇒ `mode == .git`. The reverse is asserted in `Tab.init`.
- Bundled font registration must succeed at launch — `AppDelegate.assertBundledFontsRegistered()` will fail loud if `ATSApplicationFontsPath` is misconfigured.
- A terminal surface is registered with `TerminalSurfaceRegistry` for the lifetime of its tab; injection that arrives before registration sees an empty queue and fails fast with `"No surface registered"`.
