import Foundation
import SwiftUI

/// The type of modal currently being displayed.
enum ModalType: Identifiable {
  case startupPage
  case folderSelector(AgentType)

  case settings

  var id: String {
    switch self {
    case .startupPage:
      return "startupPage"
    case .folderSelector(let agent):
      return "folderSelector-\(agent.rawValue)"
    case .settings:
      return "settings"
    }
  }
}

/// Global application state managing tabs and UI state.
@MainActor
@Observable
class AppState {
  var tabs: [Tab] = []
  var activeTabID: UUID?
  var isSidebarVisible: Bool
  var sidebarWidth: CGFloat {
    didSet {
      guard sidebarWidth != configManager.config.sidebarWidth else {
        return
      }

      configManager.config.sidebarWidth = sidebarWidth
    }
  }
  var activeModal: ModalType?
  private(set) var injectionOrchestrator: InjectionOrchestrator?
  var telegramRuntime: TelegramBotRuntime?

  /// Section to navigate to when the native Settings window opens.
  var pendingSettingsSection: SettingsSection?

  /// Shared working directory preselected across tabs within this session.
  var globalWorkingDirectory: URL?

  private var configManager = ConfigManager.shared

  init() {
    let config = ConfigManager.shared.config
    self.isSidebarVisible = config.showSidebarByDefault
    self.sidebarWidth = config.sidebarWidth

    self.injectionOrchestrator = InjectionOrchestrator(
      registry: TerminalSurfaceRegistry.shared,
      tabProvider: self
    )
  }

  /// Returns the currently active tab, if any.
  var activeTab: Tab? {
    guard let activeTabID else {
      return nil
    }

    return tabs.first { $0.id == activeTabID }
  }

  /// Creates a new tab with the specified agent and working directory.
  func createTab(
    agent: AgentType,
    directory: URL,
    initialPrompt: SavedPrompt? = nil,
    launchArgumentsOverride: [String]? = nil
  ) {
    let tab = Tab(
      agentType: agent,
      workingDirectory: directory,
      initialPrompt: initialPrompt,
      launchArgumentsOverride: launchArgumentsOverride
    )
    tabs.append(tab)
    switchToTab(id: tab.id)
  }

  /// Creates a new chat tab with the specified working directory and agent.
  func createChatTab(
    agent: AgentType = .claude,
    directory: URL,
    initialPrompt: String? = nil,
    resumeSessionId: String? = nil
  ) {
    let tab = Tab(
      agentType: agent,
      workingDirectory: directory,
      mode: .chat,
      resumeSessionId: resumeSessionId
    )
    tabs.append(tab)
    switchToTab(id: tab.id)

    /// Send initial prompt if provided.
    if let prompt = initialPrompt,
       !prompt.isEmpty
    {
      tab.chatState?.sendMessage(prompt)
    }
  }

  /// Starts the Telegram bot as a sidebar service.
  func startTelegramBot(directory: URL) {
    guard telegramRuntime == nil else {
      return
    }

    let runtime = TelegramBotRuntime(workingDirectory: directory)
    runtime.delegate = self
    telegramRuntime = runtime

    if configManager.config.telegramAutoStartOnOpen {
      runtime.start()
    }
  }

  /// Stops and removes the Telegram bot runtime.
  func stopTelegramBot() {
    telegramRuntime?.stop()
    telegramRuntime = nil
  }

  /// Closes the tab with the specified ID.
  func closeTab(id: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else {
      return
    }

    /// Terminate chat process if active.
    tabs[index].chatState?.terminateProcess()

    tabs.remove(at: index)

    /// If we closed the active tab, switch to another one.
    if activeTabID == id {
      if let nextTab = tabs.first {
        switchToTab(id: nextTab.id)
      } else {
        activeTabID = nil
      }
    }
  }

  /// Switches to the tab with the specified ID.
  func switchToTab(id: UUID) {
    /// Deactivate current tab.
    if let currentTab = activeTab {
      currentTab.isActive = false
    }

    /// Activate new tab.
    activeTabID = id
    if let newTab = activeTab {
      newTab.isActive = true
    }
  }

  /// Shows the startup page for creating a new session.
  func showStartupPage() {
    activeModal = .startupPage
  }

  /// Shows the folder selector for creating a new tab with the specified agent.
  func showFolderSelector(for agent: AgentType) {
    activeModal = .folderSelector(agent)
  }

  /// Opens the native Settings window, optionally navigating to a specific section.
  /// NOTE: Prefer using `SettingsLink` in views. This fallback exists for non-view contexts.
  func showSettings(section: SettingsSection? = nil) {
    pendingSettingsSection = section

    if #available(macOS 14.0, *) {
      NSApp.activate()
      NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
  }

  /// Dismisses the current modal.
  func dismissModal() {
    activeModal = nil
  }

  /// Toggles sidebar visibility.
  func toggleSidebar() {
    isSidebarVisible.toggle()
  }

  /// Terminates all active PTY sessions, chat responses, and bot runtimes.
  /// Called during app quit to ensure child processes are cleaned up.
  func terminateAllSessions() {
    for tab in tabs {
      /// terminateProcess() calls store.saveImmediately() internally.
      tab.chatState?.terminateProcess()
    }
    telegramRuntime?.stop()
  }
}

// MARK: - Injection

extension AppState {
  /// Submits an injection request and returns it with updated status.
  @discardableResult
  func inject(_ request: InjectionRequest) -> InjectionRequest? {
    injectionOrchestrator?.submit(request)
  }

  /// Cancels a pending injection request.
  func cancelInjection(id: UUID) {
    injectionOrchestrator?.cancel(requestId: id)
  }

  /// Returns all tab IDs with a live registered terminal surface.
  func listInjectableTabs() -> [UUID] {
    TerminalSurfaceRegistry.shared.registeredTabIds()
  }
}

// MARK: - InjectionTabProvider

extension AppState: InjectionTabProvider {
  var activeTabId: UUID? { activeTabID }

  func terminalTabs(agentType: AgentType?, mode: TabMode?) -> [UUID] {
    tabs.filter { tab in
      guard tab.mode == .terminal else {
        return false
      }

      if let mode, tab.mode != mode {
        return false
      }

      if let agentType, tab.agentType != agentType {
        return false
      }

      return true
    }.map(\.id)
  }
}

// MARK: - TelegramBotDelegate

extension AppState: TelegramBotDelegate {
  func telegramBotRequestReport() -> String {
    if tabs.isEmpty {
      return "No tabs open."
    }

    var lines = ["Open tabs (\(tabs.count)):"]
    for (index, tab) in tabs.enumerated() {
      let marker = tab.id == activeTabID ? " [active]" : ""
      let status = tabStatusForTelegramReport(tab)
      let directory = compactTelegramPath(tab.workingDirectory)
      lines.append("\(index + 1)) \(tab.tabName) (\(status)) \(directory)\(marker)")
    }

    if let activeTab {
      lines.append("Selected directory: \(compactTelegramPath(activeTab.workingDirectory))")
    }

    return lines.joined(separator: "\n")
  }

  func telegramBotOpenTab(mode: TabMode, agent: AgentType, directory: URL) {
    if mode == .chat {
      createChatTab(agent: agent, directory: directory)
    } else {
      createTab(agent: agent, directory: directory)
    }
  }

  func telegramBotListRelayableTabs() -> [TelegramRelayTabInfo] {
    let registeredIds = Set(TerminalSurfaceRegistry.shared.registeredTabIds())
    return tabs
      .filter { $0.mode == .terminal && registeredIds.contains($0.id) }
      .map {
        TelegramRelayTabInfo(
          id: $0.id,
          name: $0.tabName,
          agentType: $0.agentType,
          directory: $0.workingDirectory,
          isActive: $0.id == activeTabID
        )
      }
  }

  func telegramBotActiveInjectableAITab() -> TelegramRelayTabInfo? {
    guard let tab = activeTab,
          tab.mode == .terminal,
          (tab.agentType == .claude || tab.agentType == .opencode)
    else {
      return nil
    }

    let registeredIds = Set(TerminalSurfaceRegistry.shared.registeredTabIds())

    guard registeredIds.contains(tab.id) else {
      return nil
    }

    return TelegramRelayTabInfo(
      id: tab.id,
      name: tab.tabName,
      agentType: tab.agentType,
      directory: tab.workingDirectory,
      isActive: true
    )
  }

  func telegramBotInject(_ request: InjectionRequest) -> InjectionRequest? {
    inject(request)
  }

  func telegramBotStartupStatement(workingDirectory: URL) async -> String {
    let repoRoot = await GitService.shared.getRepositoryRoot(for: workingDirectory)

    let openTabCount = tabs.count

    return TelegramStartupStatement.compose(
      repositoryPath: repoRoot?.path,
      workingDirectoryPath: workingDirectory.path,
      openTabCount: openTabCount
    )
  }

  private func compactTelegramPath(_ directory: URL) -> String {
    let fullPath = directory.path
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path

    if fullPath.hasPrefix(homeDirectory) {
      return "~" + fullPath.dropFirst(homeDirectory.count)
    }

    return fullPath
  }

  private func tabStatusForTelegramReport(_ tab: Tab) -> String {
    switch tab.mode {
    case .chat:
      if let chatState = tab.chatState {
        return chatState.sessionState.isProcessingTurn ? "processing" : "idle"
      }

      return "idle"

    case .terminal:
      return "interactive"
    }
  }
}
