import Foundation
import SwiftUI

/// The type of modal currently being displayed.
enum ModalType: Identifiable {
  case newTab(AgentType?)
  case folderSelector(AgentType)
  case chatFolderSelector
  case settings

  var id: String {
    switch self {
    case .newTab(let agent):
      return "newTab-\(agent?.rawValue ?? "none")"
    case .folderSelector(let agent):
      return "folderSelector-\(agent.rawValue)"
    case .chatFolderSelector:
      return "chatFolderSelector"
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
  var sidebarWidth: CGFloat
  var activeModal: ModalType?
  private var configManager = ConfigManager.shared

  init() {
    let config = ConfigManager.shared.config
    self.isSidebarVisible = config.showSidebarByDefault
    self.sidebarWidth = config.sidebarWidth
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

  /// Creates a new chat tab with the specified working directory.
  func createChatTab(
    directory: URL,
    initialPrompt: String? = nil,
    resumeSessionId: String? = nil
  ) {
    let tab = Tab(
      agentType: .claude,
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

  /// Shows the chat folder selector modal.
  func showChatFolderSelector() {
    activeModal = .chatFolderSelector
  }

  /// Closes the tab with the specified ID.
  func closeTab(id: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else {
      return
    }

    /// Terminate the PTY session if active.
    tabs[index].ptyController?.terminate()

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

  /// Dismisses the current modal.
  func dismissModal() {
    activeModal = nil
  }

  /// Toggles sidebar visibility.
  func toggleSidebar() {
    isSidebarVisible.toggle()
  }

  /// Terminates all active PTY sessions and chat responses.
  /// Called during app quit to ensure child processes are cleaned up.
  func terminateAllSessions() {
    for tab in tabs {
      tab.ptyController?.terminate()
      /// terminateProcess() calls store.saveImmediately() internally.
      tab.chatState?.terminateProcess()
    }
  }
}
