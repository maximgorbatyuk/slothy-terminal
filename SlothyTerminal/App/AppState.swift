import Foundation
import SwiftUI

/// The type of modal currently being displayed.
enum ModalType: Identifiable {
  case newTab(AgentType?)
  case folderSelector(AgentType)
  case settings

  var id: String {
    switch self {
    case .newTab(let agent):
      return "newTab-\(agent?.rawValue ?? "none")"
    case .folderSelector(let agent):
      return "folderSelector-\(agent.rawValue)"
    case .settings:
      return "settings"
    }
  }
}

/// Global application state managing tabs and UI state.
@Observable
class AppState {
  var tabs: [Tab] = []
  var activeTabID: UUID?
  var isSidebarVisible: Bool = true
  var sidebarWidth: CGFloat = 260
  var activeModal: ModalType?

  /// Returns the currently active tab, if any.
  var activeTab: Tab? {
    guard let activeTabID else {
      return nil
    }

    return tabs.first { $0.id == activeTabID }
  }

  /// Creates a new tab with the specified agent and working directory.
  func createTab(agent: AgentType, directory: URL) {
    let tab = Tab(agentType: agent, workingDirectory: directory)
    tabs.append(tab)
    switchToTab(id: tab.id)
  }

  /// Closes the tab with the specified ID.
  func closeTab(id: UUID) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else {
      return
    }

    /// Terminate the PTY session if active.
    tabs[index].ptyController?.terminate()
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
}
