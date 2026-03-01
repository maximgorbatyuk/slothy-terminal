import Foundation
import SwiftUI

/// The type of modal currently being displayed.
enum ModalType: Identifiable {
  case startupPage
  case folderSelector(AgentType)
  case telegramBotFolderSelector
  case settings
  case addTask
  case taskDetail(UUID)

  var id: String {
    switch self {
    case .startupPage:
      return "startupPage"
    case .folderSelector(let agent):
      return "folderSelector-\(agent.rawValue)"
    case .telegramBotFolderSelector:
      return "telegramBotFolderSelector"
    case .settings:
      return "settings"
    case .addTask:
      return "addTask"
    case .taskDetail(let id):
      return "taskDetail-\(id.uuidString)"
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
  var sidebarWidth: CGFloat
  var activeModal: ModalType?
  var taskQueueState = TaskQueueState()
  var taskOrchestrator: TaskOrchestrator?
  private(set) var injectionOrchestrator: InjectionOrchestrator?

  /// Shared working directory preselected across tabs within this session.
  var globalWorkingDirectory: URL?

  private var configManager = ConfigManager.shared

  init() {
    let config = ConfigManager.shared.config
    self.isSidebarVisible = config.showSidebarByDefault
    self.sidebarWidth = config.sidebarWidth
    taskQueueState.restoreFromDisk()

    self.injectionOrchestrator = InjectionOrchestrator(
      registry: TerminalSurfaceRegistry.shared,
      tabProvider: self
    )

    let orchestrator = TaskOrchestrator(queueState: taskQueueState)
    self.taskOrchestrator = orchestrator

    let injectionRouter = TaskInjectionRouter(provider: self)
    orchestrator.injectionRouter = injectionRouter

    taskQueueState.onQueueChanged = { [weak orchestrator] in
      orchestrator?.notifyQueueChanged()
    }
    orchestrator.start()
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

  /// Creates a new Telegram bot tab with the specified working directory.
  func createTelegramBotTab(directory: URL) {
    if let existingBotTab = existingTelegramBotTab() {
      switchToTab(id: existingBotTab.id)
      return
    }

    let tab = Tab(
      agentType: configManager.config.telegramExecutionAgent,
      workingDirectory: directory,
      mode: .telegramBot
    )

    let runtime = TelegramBotRuntime(workingDirectory: directory)
    runtime.delegate = self
    tab.telegramRuntime = runtime

    tabs.append(tab)
    switchToTab(id: tab.id)
  }

  /// Shows the Telegram bot folder selector modal.
  func showTelegramFolderSelector() {
    if let existingBotTab = existingTelegramBotTab() {
      switchToTab(id: existingBotTab.id)
      return
    }

    activeModal = .telegramBotFolderSelector
  }

  private func existingTelegramBotTab() -> Tab? {
    tabs.first { $0.mode == .telegramBot }
  }

  /// Closes the tab with the specified ID.
  func closeTab(id: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else {
      return
    }

    /// Terminate chat process if active.
    tabs[index].chatState?.terminateProcess()

    /// Stop Telegram bot if active.
    tabs[index].telegramRuntime?.stop()

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

  /// Shows the settings modal.
  func showSettings() {
    activeModal = .settings
  }

  /// Shows the add task modal.
  func showAddTaskModal() {
    activeModal = .addTask
  }

  /// Shows the task detail modal.
  func showTaskDetail(id: UUID) {
    activeModal = .taskDetail(id)
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
      tab.telegramRuntime?.stop()
    }
    taskOrchestrator?.stop()
    taskQueueState.saveImmediately()
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

// MARK: - TaskInjectionProvider

extension AppState: TaskInjectionProvider {
  func injectableTabCandidates(agentType: AgentType) -> [InjectableTabCandidate] {
    let registeredIds = Set(TerminalSurfaceRegistry.shared.registeredTabIds())

    return tabs.compactMap { tab in
      guard tab.mode == .terminal,
            tab.agentType == agentType
      else {
        return nil
      }

      return InjectableTabCandidate(
        tabId: tab.id,
        agentType: tab.agentType,
        workingDirectory: tab.workingDirectory,
        isActive: tab.id == activeTabID,
        isRegistered: registeredIds.contains(tab.id)
      )
    }
  }

  func submitInjection(_ request: InjectionRequest) -> InjectionRequest? {
    injectionOrchestrator?.submit(request)
  }

  func cancelInjection(requestId: UUID) {
    injectionOrchestrator?.cancel(requestId: requestId)
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

    let pendingCount = taskQueueState.tasks.filter { $0.status == .pending }.count
    let runningCount = taskQueueState.tasks.filter { $0.status == .running }.count
    lines.append("Task queue: pending \(pendingCount), running \(runningCount)")

    return lines.joined(separator: "\n")
  }

  func telegramBotOpenTab(mode: TabMode, agent: AgentType, directory: URL) {
    if mode == .chat {
      createChatTab(agent: agent, directory: directory)
    } else {
      createTab(agent: agent, directory: directory)
    }
  }

  func telegramBotEnqueueTask(
    title: String,
    prompt: String,
    repoPath: String,
    agentType: AgentType
  ) {
    taskQueueState.enqueueTask(
      title: title,
      prompt: prompt,
      repoPath: repoPath,
      agentType: agentType
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

    case .telegramBot:
      if let runtime = tab.telegramRuntime {
        switch runtime.status {
        case .idle:
          return "idle"

        case .running:
          return "running (\(runtime.mode.displayName.lowercased()))"

        case .error:
          return "error"
        }
      }

      return "idle"
    }
  }
}
