import SwiftUI

@main
struct SlothyTerminalApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var appState = AppState()
  @Environment(\.openWindow) private var openWindow
  private var configManager = ConfigManager.shared

  var body: some Scene {
    WindowGroup {
      MainView()
        .environment(appState)
        .preferredColorScheme(configManager.config.colorScheme.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .newTabRequested)) { notification in
          if let agentType = notification.userInfo?["agentType"] as? AgentType {
            appState.showFolderSelector(for: agentType)
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChatTabRequested)) { notification in
          let agent = notification.userInfo?["agentType"] as? AgentType ?? .claude
          appState.showChatFolderSelector(for: agent)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFolderRequested)) { notification in
          if let folder = notification.userInfo?["folder"] as? URL,
             let agentType = notification.userInfo?["agentType"] as? AgentType
          {
            appState.createTab(agent: agentType, directory: folder)
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
          appState.terminateAllSessions()
        }
    }
    .windowStyle(.titleBar)
    .commands {
      /// About menu.
      CommandGroup(replacing: .appInfo) {
        Button("About \(BuildConfig.current.appName)") {
          openWindow(id: "about")
        }
      }

      /// App menu - Check for Updates.
      CommandGroup(after: .appInfo) {
        Button("Check for Updates...") {
          UpdateManager.shared.checkForUpdates()
        }
        .disabled(!UpdateManager.shared.canCheckForUpdates)
      }

      /// File menu.
      CommandGroup(replacing: .newItem) {
        Button("New Chat Tab") {
          appState.showChatFolderSelector()
        }
        .keyboardShortcut("t", modifiers: .command)

        Button("New Claude TUI Tab") {
          appState.showFolderSelector(for: .claude)
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])

        Button("New OpenCode Chat Tab") {
          appState.showChatFolderSelector(for: .opencode)
        }
        .keyboardShortcut("t", modifiers: [.command, .option])

        Divider()

        Button("New OpenCode TUI Tab") {
          appState.showFolderSelector(for: .opencode)
        }

        Button("New Terminal Tab") {
          appState.showFolderSelector(for: .terminal)
        }
        .keyboardShortcut("t", modifiers: [.command, .shift, .option])

        Button("New Telegram Bot Tab") {
          appState.showTelegramFolderSelector()
        }

        Divider()

        Button("Open Folder...") {
          appState.showFolderSelector(for: configManager.config.defaultAgent)
        }
        .keyboardShortcut("o", modifiers: .command)

        Divider()

        Button("Close Tab") {
          if let activeTab = appState.activeTab {
            appState.closeTab(id: activeTab.id)
          }
        }
        .keyboardShortcut("w", modifiers: .command)
        .disabled(appState.activeTab == nil)
      }

      /// View menu.
      CommandGroup(after: .sidebar) {
        Button("Toggle Sidebar") {
          appState.toggleSidebar()
        }
        .keyboardShortcut("b", modifiers: .command)
      }

      /// Window menu - tab navigation.
      CommandGroup(after: .windowArrangement) {
        Divider()

        Button("Next Tab") {
          navigateToNextTab()
        }
        .keyboardShortcut("]", modifiers: [.command, .shift])
        .disabled(appState.tabs.count < 2)

        Button("Previous Tab") {
          navigateToPreviousTab()
        }
        .keyboardShortcut("[", modifiers: [.command, .shift])
        .disabled(appState.tabs.count < 2)
      }

      /// Help menu.
      CommandGroup(replacing: .help) {
        Button("SlothyTerminal Help") {
          if let url = URL(string: "https://github.com/slothy-terminal/help") {
            NSWorkspace.shared.open(url)
          }
        }
      }

      /// Tab switching shortcuts (Cmd+1 through Cmd+9).
      CommandGroup(after: .windowArrangement) {
        ForEach(1...9, id: \.self) { index in
          Button("Switch to Tab \(index)") {
            switchToTabAtIndex(index - 1)
          }
          .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
          .disabled(appState.tabs.count < index)
        }
      }
    }

    Settings {
      SettingsView()
        .environment(appState)
        .preferredColorScheme(configManager.config.colorScheme.colorScheme)
    }

    Window("About \(BuildConfig.current.appName)", id: "about") {
      AboutView()
        .preferredColorScheme(configManager.config.colorScheme.colorScheme)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
  }

  private func navigateToNextTab() {
    guard let currentTab = appState.activeTab,
          let currentIndex = appState.tabs.firstIndex(where: { $0.id == currentTab.id })
    else {
      return
    }

    let nextIndex = (currentIndex + 1) % appState.tabs.count
    appState.switchToTab(id: appState.tabs[nextIndex].id)
  }

  private func navigateToPreviousTab() {
    guard let currentTab = appState.activeTab,
          let currentIndex = appState.tabs.firstIndex(where: { $0.id == currentTab.id })
    else {
      return
    }

    let previousIndex = currentIndex == 0 ? appState.tabs.count - 1 : currentIndex - 1
    appState.switchToTab(id: appState.tabs[previousIndex].id)
  }

  private func switchToTabAtIndex(_ index: Int) {
    guard index >= 0, index < appState.tabs.count else {
      return
    }

    appState.switchToTab(id: appState.tabs[index].id)
  }
}
