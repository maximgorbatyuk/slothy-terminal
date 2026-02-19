import Foundation
import SwiftUI

/// The type of modal currently being displayed.
enum ModalType: Identifiable {
  case newTab(AgentType?)
  case folderSelector(AgentType)
  case chatFolderSelector(AgentType)
  case telegramBotFolderSelector
  case settings
  case addTask
  case taskDetail(UUID)

  var id: String {
    switch self {
    case .newTab(let agent):
      return "newTab-\(agent?.rawValue ?? "none")"
    case .folderSelector(let agent):
      return "folderSelector-\(agent.rawValue)"
    case .chatFolderSelector(let agent):
      return "chatFolderSelector-\(agent.rawValue)"
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
  private var configManager = ConfigManager.shared

  init() {
    let config = ConfigManager.shared.config
    self.isSidebarVisible = config.showSidebarByDefault
    self.sidebarWidth = config.sidebarWidth
    taskQueueState.restoreFromDisk()

    let orchestrator = TaskOrchestrator(queueState: taskQueueState)
    self.taskOrchestrator = orchestrator
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
  func createTab(agent: AgentType, directory: URL, initialPrompt: SavedPrompt? = nil) {
    let tab = Tab(agentType: agent, workingDirectory: directory, initialPrompt: initialPrompt)
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

  /// Shows the chat folder selector modal for the specified agent.
  func showChatFolderSelector(for agent: AgentType = .claude) {
    activeModal = .chatFolderSelector(agent)
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

  /// Shows the new tab modal, optionally pre-selecting an agent.
  func showNewTabModal(agent: AgentType? = nil) {
    activeModal = .newTab(agent)
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
