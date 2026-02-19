# ST-3 Development Plan: Reworked Starting Page

## Feature statement (from `FEATURES.md`)

ST-3 requirement:

- Rework the starting page.
- Show launch type selector with options: Terminal, Claude Chat, OpenCode Chat, Claude Desktop App, Codex Desktop App, Telegram Bot.
- Show prompt selector (disabled when Telegram Bot is selected).
- Show "Start" button.

Related ST-4 requirement (folder selection on starting screen):

- Folder selector should be placed at the center.
- Clicking the selector opens modal with last folders and folder browser.
- Selected folder should be preselected in other tabs.

## Current baseline

The current `AgentSelectionView` in `MainView.swift:199` provides:

- Header "Open new tab"
- Working directory selection
- Prompt picker (if saved prompts exist)
- Tab type buttons organized by:
  - Chat mode buttons (for agents supporting chat)
  - TUI/terminal mode buttons (all agents)

What needs to change:

- Single-select launch type instead of multiple action buttons.
- Add new launch types: Claude Desktop, Codex Desktop, Telegram Bot.
- Conditional prompt selector (disabled for Telegram).
- Prominent "Start" button.
- Center-aligned folder selector (per ST-4).

## Scope and assumptions

- ST-3 depends on ST-1 (Telegram Bot) and ST-2 (Desktop Launch) being available.
- If ST-1/ST-2 are not yet implemented, those options should be disabled or hidden.
- The starting page is a modal sheet triggered from File menu or Cmd+T.
- Selected folder persists across tabs within the same session.

## High-level architecture

### 1) Launch type model

Create `LaunchType` enum replacing direct agent selection:

```swift
enum LaunchType: String, CaseIterable, Identifiable {
  case terminal
  case claudeChat
  case opencodeChat
  case claudeDesktop
  case codexDesktop
  case telegramBot

  var id: String { rawValue }

  var displayName: String
  var subtitle: String
  var iconName: String
  var accentColor: Color
  var requiresPrompt: Bool
  var availabilityCheck: () -> Bool
}
```

Availability:

- `terminal`: always available
- `claudeChat`, `opencodeChat`: check CLI availability
- `claudeDesktop`, `codexDesktop`: check `ExternalAppManager` installation
- `telegramBot`: check Telegram config (token + allowed user ID set)

### 2) Reworked starting page view

Replace `AgentSelectionView` with new `StartupPageView`:

- Centered layout with stacked sections:
  1. Folder selector (prominent, center, clickable card)
  2. Launch type dropdown selector (single Menu/Pickers)
  3. Prompt selector (conditionally shown/enabled, dropdown style)
- Bottom action area with "Start" button

### 3) Folder selector integration

Reuse `FolderSelectorModal` but expose a compact inline trigger:

- Large clickable folder card at center.
- On click, open existing `FolderSelectorModal` as sheet.
- Display selected path with icon.

### 4) Launch type selector

Use a dropdown menu (Picker with `.menu` style) instead of grid:

- Shows current selection with chevron indicator.
- Dropdown lists all available launch types.
- Unavailable types shown with "(not installed)" suffix and disabled.
- Icons displayed next to each option for visual recognition.

### 5) Start action routing

Single "Start" button routes to appropriate handler:

```swift
func handleStart() {
  switch selectedLaunchType {
  case .terminal:
    appState.createTab(agent: selectedAgent, directory: selectedFolder, initialPrompt: selectedPrompt)
  case .claudeChat, .opencodeChat:
    appState.createChatTab(agent: selectedAgent, directory: selectedFolder, initialPrompt: selectedPrompt?.promptText)
  case .claudeDesktop, .codexDesktop:
    DesktopPromptLauncher.shared.launch(target: desktopTarget, directory: selectedFolder, prompt: selectedPrompt)
  case .telegramBot:
    appState.createTelegramBotTab(directory: selectedFolder)
  }
}
```

## App integration plan

### 1) Model additions

Add to `AppState`:

- `globalWorkingDirectory: URL?` - shared folder preselected across tabs
- `createTelegramBotTab(directory:)` - new method (depends on ST-1)

Add to `AppConfig`:

- `lastUsedLaunchType: LaunchType?` - remember user preference

### 2) View structure

```
StartupPageView
├── Header ("Start New Session")
├── FolderSelectorCard (center, large, clickable)
│   └── Opens FolderSelectorModal on click
├── LaunchTypeDropdown (Menu/Picker)
│   ├── Terminal
│   ├── Claude Chat
│   ├── OpenCode Chat
│   ├── Claude Desktop (if ST-2 ready)
│   ├── Codex Desktop (if ST-2 ready)
│   └── Telegram Bot (if ST-1 ready)
├── PromptPicker (conditional, dropdown style)
│   └── Disabled when Telegram Bot selected
└── Footer
    └── "Start" button (primary, full width)
```

### 3) Modal routing update

Update `ModalType` to use new startup page:

```swift
case .startupPage(preselectedLaunchType: LaunchType?)
```

Replace `.newTab` calls with `.startupPage`.

### 4) Menu integration

Update File menu entries:

- "New Session..." → opens startup page (Cmd+T)
- Keep existing direct shortcuts for power users:
  - Cmd+Shift+T → Claude TUI
  - Cmd+Option+T → OpenCode Chat

## UI visualization

### Default layout (no selection)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                         [X] │
│                          Start New Session                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                     ┌─────────────────────────────────┐                    │
│                     │  📁  ~/projects/my-app          │                    │
│                     │      Click to change folder     │                    │
│                     └─────────────────────────────────┘                    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   LAUNCH TYPE                                                               │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  💬  Claude Chat                                         [ ▼ ]    │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   PROMPT                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  No prompt                                             [ ▼ ]      │  │
│   │  Start without predefined prompt                                    │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                     ┌─────────────────────────────────┐                    │
│                     │           START                 │                    │
│                     └─────────────────────────────────┘                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Launch type dropdown expanded

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                         [X] │
│                          Start New Session                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                     ┌─────────────────────────────────┐                    │
│                     │  📁  ~/projects/my-app          │                    │
│                     │      Click to change folder     │                    │
│                     └─────────────────────────────────┘                    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   LAUNCH TYPE                                                               │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  💬  Claude Chat                                         [ ▼ ]    │  │
│   ├─────────────────────────────────────────────────────────────────────┤  │
│   │  🖥️  Terminal                    ─────────────────────────────────   │  │
│   │  💬  Claude Chat                  ● selected                         │  │
│   │  💬  OpenCode Chat               ─────────────────────────────────   │  │
│   │  🖥️  Claude Desktop              ─────────────────────────────────   │  │
│   │  🖥️  Codex Desktop (not installed)                                   │  │
│   │  🤖  Telegram Bot                ─────────────────────────────────   │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   PROMPT                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  Review PR                                               [ ▼ ]      │  │
│   │  Review this pull request and summarize changes...                  │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                     ┌─────────────────────────────────┐                    │
│                     │           START                 │                    │
│                     └─────────────────────────────────┘                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Telegram Bot selected (prompt disabled)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                         [X] │
│                          Start New Session                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                     ┌─────────────────────────────────┐                    │
│                     │  📁  ~/projects/my-app          │                    │
│                     │      Click to change folder     │                    │
│                     └─────────────────────────────────┘                    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   LAUNCH TYPE                                                               │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  🤖  Telegram Bot                                        [ ▼ ]    │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   PROMPT (disabled for Telegram Bot)                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  ──────────────────────────────────────────────────────────────     │  │
│   │  Telegram Bot does not use predefined prompts                       │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                     ┌─────────────────────────────────┐                    │
│                     │           START                 │                    │
│                     └─────────────────────────────────┘                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Compact layout (narrow window)

```
┌───────────────────────────────────────────┐
│                                   [X]      │
│         Start New Session                 │
├───────────────────────────────────────────┤
│                                           │
│         ┌───────────────────────────┐     │
│         │ 📁 ~/projects/my-app      │     │
│         │   Click to change folder  │     │
│         └───────────────────────────┘     │
│                                           │
├───────────────────────────────────────────┤
│                                           │
│  LAUNCH TYPE                              │
│  ┌─────────────────────────────────────┐  │
│  │ 💬 Claude Chat              [ ▼ ]  │  │
│  └─────────────────────────────────────┘  │
│                                           │
├───────────────────────────────────────────┤
│                                           │
│  PROMPT                                    │
│  ┌─────────────────────────────────────┐  │
│  │ No prompt                   [ ▼ ]   │  │
│  └─────────────────────────────────────┘  │
│                                           │
├───────────────────────────────────────────┤
│                                           │
│         ┌───────────────────────────┐     │
│         │          START            │     │
│         └───────────────────────────┘     │
│                                           │
└───────────────────────────────────────────┘
```

### Folder selector clicked (modal opens)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Select Working Directory                      [X]  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   RECENT FOLDERS                                                            │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  📁 ~/projects/app-a                            [x]                 │  │
│   │  📁 ~/projects/app-b                            [x]                 │  │
│   │  📁 ~/projects/app-c                            [x]                 │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                     ┌─────────────────────────────────┐                    │
│                     │        Browse...                │                    │
│                     └─────────────────────────────────┘                    │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│   [ Cancel ]                                                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Runtime behavior details

### Launch type selection

- Dropdown menu shows all launch types with icons.
- Current selection displayed with chevron indicator.
- Persists last selection to config.
- Prompt selector enables/disables based on `LaunchType.requiresPrompt`.
- Unavailable types shown with "(not installed)" suffix and are disabled in menu.

### Folder selection

- Click folder card → opens `FolderSelectorModal` as sheet.
- On selection, updates `globalWorkingDirectory` in `AppState`.
- Selected folder is passed to all subsequently created tabs.

### Start button

- Enabled only when:
  - Folder is selected
  - Launch type is available
  - Prompt is selected (if required by launch type)
- On click:
  - Dismiss startup page
  - Execute appropriate launch action
  - Show feedback toast if action is async (e.g., desktop launch)

## Error handling

- Launch type not available → show inline hint and disable Start.
- Folder not accessible → show error in folder card, allow reselection.
- Desktop launch failure → show error toast after modal dismisses.
- Telegram not configured → show "Configure in Settings" hint.

## Test plan

### Unit tests

1. Launch type model:
   - displayName, iconName, requiresPrompt for each case
   - availabilityCheck returns correct result
2. Prompt enablement:
   - prompt enabled for chat/terminal types
   - prompt disabled for Telegram
3. Start button validation:
   - disabled when no folder
   - disabled when type unavailable
   - disabled when prompt required but not selected

### Integration tests

1. Folder selection flow opens and closes modal correctly.
2. Start action creates correct tab type.
3. Start action launches desktop app with prompt.
4. Start action creates Telegram bot tab.
5. Selected folder persists to new tabs.

## Implementation phases

### Phase 1: Model and state

- Add `LaunchType` enum.
- Add `globalWorkingDirectory` to `AppState`.
- Add `lastUsedLaunchType` to `AppConfig`.

### Phase 2: New startup page UI

- Create `StartupPageView`.
- Implement folder selector card.
- Implement launch type picker.
- Wire prompt picker with conditional enablement.

### Phase 3: Start action routing

- Implement unified start handler.
- Integrate with existing tab creation.
- Integrate with ST-2 desktop launcher.
- Integrate with ST-1 Telegram bot (if ready).

### Phase 4: Modal and menu updates

- Replace `AgentSelectionView` usage with `StartupPageView`.
- Update modal routing.
- Update File menu entries.

### Phase 5: Hardening

- Add tests.
- Verify all launch paths.
- Accessibility and keyboard navigation.

## Acceptance criteria

1. User sees a centered folder selector on startup page.
2. User can select from six launch types (Terminal, Claude Chat, OpenCode Chat, Claude Desktop, Codex Desktop, Telegram Bot).
3. Prompt selector is disabled when Telegram Bot is selected.
4. "Start" button creates/launches the selected session type.
5. Unavailable launch types are visibly disabled with hint.
6. Selected folder is preselected in all new tabs.
7. Last used launch type is remembered across sessions.

## Dependencies

- ST-1 (Telegram Bot) - for Telegram Bot launch type
- ST-2 (Desktop Launch) - for Claude Desktop and Codex Desktop launch types

If ST-1 or ST-2 are not implemented:
- Hide corresponding launch types OR
- Show with "Coming soon" badge and disable
