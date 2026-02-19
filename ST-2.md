# ST-2 Development Plan: Launch Claude Desktop and Codex with Predefined Prompt

## Feature statement (from `FEATURES.md`)

ST-2 requirement:

- Launch Claude Desktop app and Codex desktop app.
- Launch must include a predefined prompt.

## Current baseline in project

The codebase already has strong pieces we can reuse:

- `ExternalAppManager` detects installed apps and opens URLs/directories in specific apps.
  - Claude Desktop bundle id: `com.anthropic.claudefordesktop`
  - Codex bundle id: `com.openai.codex`
- Saved prompts are already implemented (`SavedPrompt`, Prompts settings, prompt picker UI).
- Folder/prompt selection flow already exists in `AgentSelectionView` and `FolderSelectorModal`.

Main missing piece for ST-2:

- Prompt delivery into desktop app composer (not only opening the app).

## Scope and assumptions

- ST-2 is implemented independently from ST-3 startup-page redesign.
- Prompt source is existing Saved Prompts (selected by user in launch flow).
- A selected predefined prompt is required for desktop app launch actions.
- If native deep-link prompt injection is unavailable, fallback path still launches app and prepares prompt for immediate paste.

## High-level architecture

### 1) Add a dedicated desktop launch target model

Create `DesktopAppTarget` (new enum), for:

- `.claudeDesktop`
- `.codexDesktop`

Each case provides:

- display name
- bundle identifier
- icon/accent metadata for UI

### 2) Add a desktop prompt launcher service

Create `DesktopPromptLauncher` service with API like:

- `launch(target: DesktopAppTarget, directory: URL, prompt: SavedPrompt) async -> DesktopLaunchResult`

Responsibilities:

- validate installation
- launch app via `NSWorkspace`
- deliver prompt text using strategy chain
- return structured result for UI feedback

### 3) Prompt delivery strategy chain

Implement a strategy order to maximize reliability:

1. `URLSchemePromptDelivery` (preferred)
   - Use app-specific deep link if available (prompt prefilled/opened in chat composer).
2. `ClipboardPromptDelivery` (guaranteed fallback)
   - Copy prompt to pasteboard.
   - Bring app to front.
   - Show in-app hint: "Prompt copied. Paste with Cmd+V".

Optional phase (if needed later):

3. `AppleScriptAutoPasteDelivery`
   - Auto-paste into focused app input.
   - Requires Accessibility permission and is less deterministic.

## Discovery and compatibility step

Before coding delivery logic, run a short capability probe on target apps:

- Verify app availability by bundle id.
- Inspect whether Claude Desktop and Codex expose stable prompt deep links.
- If deep links are unsupported or unstable, set Clipboard fallback as default path.

Deliverable from this step:

- Explicit per-app launch strategy table in code comments/docs.

## App integration plan

### 1) Config additions (`AppConfig`)

Add minimal desktop-launch settings:

- `desktopPromptLaunchPreferredMethod: DesktopPromptLaunchMethod` (`auto`, `urlScheme`, `clipboard`)
- optional app-specific URL templates (only if needed after discovery)

No secrets required for ST-2.

### 2) UI entry points

Integrate into existing launch surface now (without waiting for ST-3):

- `AgentSelectionView`:
  - Add "Desktop Apps" section with two actions:
    - "Launch Claude Desktop"
    - "Launch Codex"
  - Reuse existing selected directory + selected prompt.
- Disable launch buttons when:
  - app is not installed
  - no prompt selected

User feedback:

- success toast/message (app launched, prompt delivery method used)
- failure message with reason (not installed, launch error, prompt delivery error)

### 3) Optional menu shortcuts

Add File menu entries:

- `Launch Claude Desktop with Prompt...`
- `Launch Codex with Prompt...`

These open the same selection flow and then call `DesktopPromptLauncher`.

## Detailed runtime behavior

### Launch flow

1. User selects directory and predefined prompt.
2. User chooses target desktop app.
3. App checks installation and validates prompt text is non-empty.
4. App launches target desktop app.
5. Prompt is delivered by configured strategy chain.
6. UI shows result with explicit method used:
   - "Delivered via deep link"
   - "Copied to clipboard"

### Directory behavior

- Directory is selected in Slothy launch flow.
- Launcher also attempts to open directory in target app when meaningful.
- If target app does not use directory context, this is non-fatal and prompt delivery still proceeds.

## Error handling

- App missing -> show actionable "Install app" message.
- Deep-link delivery failure -> automatic fallback to clipboard delivery.
- Clipboard write failure -> return explicit error and keep app launch result visible.
- Empty prompt text -> block launch with validation message.

## Test plan

### Unit tests

1. Target resolution:
   - bundle id/name mapping for Claude Desktop and Codex.
2. Launcher validation:
   - rejects when prompt is empty.
   - rejects when app not installed.
3. Strategy chain:
   - deep-link success path used when available.
   - deep-link failure falls back to clipboard.
4. Result mapping:
   - UI messages reflect final method/outcome.

### Integration tests (with service mocks)

1. Launch Claude Desktop with selected prompt and directory.
2. Launch Codex with selected prompt and directory.
3. Not-installed path disables action and surfaces correct error.
4. Clipboard fallback path completes with success feedback.

## Implementation phases

### Phase 1: Discovery and abstractions

- Add `DesktopAppTarget` and launcher interfaces.
- Probe deep-link capabilities and lock default strategy.

### Phase 2: Launcher implementation

- Implement `DesktopPromptLauncher`.
- Implement URL-scheme + clipboard delivery strategies.

### Phase 3: UI integration

- Add desktop launch actions to `AgentSelectionView`.
- Add validation and user feedback.

### Phase 4: Hardening

- Add tests.
- Verify behavior on machines with/without each app installed.

## Acceptance criteria

1. User can launch Claude Desktop from Slothy using a selected predefined prompt.
2. User can launch Codex desktop from Slothy using a selected predefined prompt.
3. Launch actions are disabled or clearly error when target app is not installed.
4. Prompt delivery path is reliable (deep-link when supported, clipboard fallback otherwise).
5. User receives clear success/failure feedback for every launch attempt.
