# Roadmap

## Features

- [x] STF-1. Show a list of app to open in the current folder. Apps: Ghosty, Cursor, Antigravity, VSCode, iTerm, etc. The applization should find apps by itself.
- [x] STF-2. The app should show files and folders in the current folder. Subfolders should be shown in a tree view.
- [x] STF-3. Use Ghostty terminal to run commands. Terminal rendering is powered by libghostty (Metal-accelerated) via `GhosttyApp` singleton and `GhosttySurfaceView`.
- [x] STF-4. Show current Git branch in left corner of the bottom line. If there is no git branch, show nothing.
- [ ] STF-5. Fetch claude usage stats on the background and show it on the sidebar.
- [ ] STF-6. Add Custom UI for Claude as tab option (claude-custom-ui.md)
- [ ] STF-7. Open OpenCode chat with predefined model, mode (build/plan), and reasoning level.
  - Model + mode are partially supported today via last-used persistence, but not explicit per-tab launch params.
  - Reasoning level is not implemented in the app yet; OpenCode CLI supports it via `--variant` (for example: `minimal`, `high`, `max`).
  - Transport already passes `--model` and `--agent`; adding `--variant` is straightforward.
  - Plan: add optional launch params to `createChatTab(...)` and wire them through `Tab` -> `ChatState` -> `OpenCodeCLITransport`.
- [x] STF-8. Auto-scroll chat to bottom while the agent is writing messages.
  - Implemented in `ChatMessageListView` via `ScrollViewReader` with `onChange` tracking last message text during streaming.

## Findings

- [x] STB-1. Text from console is not selectable and it is not possible to copy it.
- [x] STB-2. Claude placeholder has same color as main text. It should be more gray
- [x] STB-3. In settings there are inconsistent colors.
- [x] STB-4. When I open second tab and paste there anything, the text appears in the first tab.
