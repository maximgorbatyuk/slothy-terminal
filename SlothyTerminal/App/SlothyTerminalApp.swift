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
        .appFont(configManager.config.appFont)
        .onAppear {
          /// Attach the Finder Services sink and drain any cold-launch
          /// requests queued before the scene was ready.
          FinderServiceRequestQueue.shared.attach { request in
            switch request {
            case .newTab(let folder):
              appState.createTab(agent: .terminal, directory: folder)

            case .newWindow(let folder):
              appState.createWorkspaceAndTerminalTab(directory: folder)
            }
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTabRequested)) { notification in
          if let agentType = notification.userInfo?["agentType"] as? AgentType {
            appState.showFolderSelector(for: agentType)
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSessionRequested)) { _ in
          openNewTerminalTab()
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
          configManager.saveImmediately()
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
        Button("New Terminal Tab") {
          openNewTerminalTab()
        }
        .keyboardShortcut("t", modifiers: .command)

        Button("New Terminal Tab in Split View") {
          openNewTerminalTabInSplit()
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
        .disabled(appState.activeTab == nil)

        Divider()

        Button("New Terminal Tab in Folder...") {
          appState.showFolderSelector(for: .terminal)
        }
        .keyboardShortcut("t", modifiers: [.command, .shift, .option])

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
        .disabled(appState.visibleTabs.count < 2)

        Button("Previous Tab") {
          navigateToPreviousTab()
        }
        .keyboardShortcut("[", modifiers: [.command, .shift])
        .disabled(appState.visibleTabs.count < 2)
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
          .disabled(appState.visibleTabs.count < index)
        }
      }
    }

    Settings {
      SettingsView()
        .environment(appState)
        .preferredColorScheme(configManager.config.colorScheme.colorScheme)
        .appFont(configManager.config.appFont)
    }

    Window("About \(BuildConfig.current.appName)", id: "about") {
      AboutView()
        .preferredColorScheme(configManager.config.colorScheme.colorScheme)
        .appFont(configManager.config.appFont)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
  }

  private func navigateToNextTab() {
    let visible = appState.visibleTabs

    guard let currentTab = appState.activeTab,
          let currentIndex = visible.firstIndex(where: { $0.id == currentTab.id })
    else {
      return
    }

    let nextIndex = (currentIndex + 1) % visible.count
    appState.switchToTab(id: visible[nextIndex].id)
  }

  private func navigateToPreviousTab() {
    let visible = appState.visibleTabs

    guard let currentTab = appState.activeTab,
          let currentIndex = visible.firstIndex(where: { $0.id == currentTab.id })
    else {
      return
    }

    let previousIndex = currentIndex == 0 ? visible.count - 1 : currentIndex - 1
    appState.switchToTab(id: visible[previousIndex].id)
  }

  /// Resolves the working directory for a new terminal tab opened via the
  /// File menu or the `.newSessionRequested` notification.
  private func directoryForNewTerminalTab() -> URL {
    appState.activeWorkspace?.rootDirectory
      ?? appState.currentContextDirectory
      ?? FileManager.default.homeDirectoryForCurrentUser
  }

  private func openNewTerminalTab() {
    appState.createTab(agent: .terminal, directory: directoryForNewTerminalTab())
  }

  private func openNewTerminalTabInSplit() {
    appState.createTabInSplit(agent: .terminal, directory: directoryForNewTerminalTab())
  }

  private func switchToTabAtIndex(_ index: Int) {
    let visible = appState.visibleTabs

    guard index >= 0, index < visible.count else {
      return
    }

    appState.switchToTab(id: visible[index].id)
  }
}
