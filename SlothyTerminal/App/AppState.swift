import Foundation
import SwiftUI

/// Result of attempting to close a workspace.
enum CloseWorkspaceResult: Equatable {
  case closed
  case hasOpenTabs
  case notFound
}

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

/// Input that determines when the status bar should re-fetch the git branch.
struct GitBranchRefreshContext: Equatable {
  let tabID: UUID
  let workingDirectory: URL
  let isTerminalBusy: Bool
}

enum TabDropIndicator: Equatable {
  case none
  case before(UUID)
  case end

  var isVisible: Bool {
    switch self {
    case .none:
      return false

    case .before,
         .end:
      return true
    }
  }
}

/// Global application state managing tabs and UI state.
@MainActor
@Observable
class AppState {
  var workspaces: [Workspace] = []
  var activeWorkspaceID: UUID?
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

  /// Preferred default directory for launching a new session.
  var preferredNewSessionDirectory: URL? {
    if let activeWorkspace {
      return activeWorkspace.rootDirectory
    }

    return globalWorkingDirectory
  }

  /// Best available directory for workspace-aware sidebars and services.
  var currentContextDirectory: URL? {
    if let activeTab {
      return activeTab.workingDirectory
    }

    return preferredNewSessionDirectory
  }

  /// Refresh context for the bottom-bar git branch display.
  var gitBranchRefreshContext: GitBranchRefreshContext? {
    guard let activeTab else {
      return nil
    }

    return GitBranchRefreshContext(
      tabID: activeTab.id,
      workingDirectory: activeTab.workingDirectory,
      isTerminalBusy: activeTab.mode == .terminal ? activeTab.isTerminalBusy : false
    )
  }

  /// Display label for a tab in the current workspace tab bar.
  func tabBarLabel(for tab: Tab) -> String {
    guard let index = visibleTabs.firstIndex(where: { $0.id == tab.id }) else {
      return tab.tabName
    }

    return "\(index + 1). \(tab.tabName)"
  }

  /// Display label for the tab awaiting close confirmation.
  var pendingCloseTabLabel: String {
    guard let id = tabPendingClose,
          let tab = tabs.first(where: { $0.id == id })
    else {
      return "this tab"
    }

    return "\"\(tabBarLabel(for: tab))\""
  }

  /// Tab awaiting close confirmation (set when user tries to close an inactive tab).
  var tabPendingClose: UUID?

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

  /// Returns the currently active workspace, if any.
  var activeWorkspace: Workspace? {
    guard let activeWorkspaceID else {
      return nil
    }

    return workspaces.first { $0.id == activeWorkspaceID }
  }

  /// Tabs belonging to the currently active workspace.
  /// When no workspace is active, returns all tabs.
  var visibleTabs: [Tab] {
    guard let activeWorkspaceID else {
      return tabs
    }

    return tabs.filter { $0.workspaceID == activeWorkspaceID }
  }

  /// Creates a new workspace from the given directory.
  @discardableResult
  func createWorkspace(from directory: URL) -> Workspace {
    let workspace = Workspace(directory: directory)
    workspaces.append(workspace)
    switchWorkspace(id: workspace.id)
    return workspace
  }

  /// Whether the workspace has any open tabs.
  func hasTabs(in workspaceID: UUID) -> Bool {
    tabs.contains { $0.workspaceID == workspaceID }
  }

  /// Returns all tabs belonging to the specified workspace.
  func tabs(in workspaceID: UUID) -> [Tab] {
    tabs.filter { $0.workspaceID == workspaceID }
  }

  /// Looks up a workspace by ID.
  func workspace(for id: UUID) -> Workspace? {
    workspaces.first { $0.id == id }
  }

  /// Switches to the workspace with the specified ID.
  /// Aligns the active tab to the selected workspace.
  func switchWorkspace(id: UUID) {
    guard workspaces.contains(where: { $0.id == id }) else {
      return
    }

    activeWorkspaceID = id

    // If current active tab already belongs to this workspace, keep it.
    if let current = activeTab, current.workspaceID == id {
      return
    }

    // Switch to first tab in the workspace, or nil if empty.
    if let firstTab = tabs.first(where: { $0.workspaceID == id }) {
      switchToTab(id: firstTab.id)
    } else {
      if let current = activeTab {
        current.isActive = false
      }
      activeTabID = nil
    }
  }

  /// Closes the workspace with the specified ID.
  /// Fails if the workspace still has open tabs.
  @discardableResult
  func closeWorkspace(id: UUID) -> CloseWorkspaceResult {
    guard workspaces.contains(where: { $0.id == id }) else {
      return .notFound
    }

    guard !hasTabs(in: id) else {
      return .hasOpenTabs
    }

    workspaces.removeAll { $0.id == id }

    if activeWorkspaceID == id {
      if let fallback = workspaces.first {
        switchWorkspace(id: fallback.id)
      } else {
        activeWorkspaceID = nil
      }
    }

    return .closed
  }

  /// Resolves the workspace ID for a new tab.
  /// Creates the first workspace from the directory if none exist;
  /// otherwise returns the active (or first) workspace ID.
  private func resolveWorkspaceID(for directory: URL) -> UUID {
    if let active = activeWorkspace {
      return active.id
    }

    if let first = workspaces.first {
      activeWorkspaceID = first.id
      return first.id
    }

    let workspace = createWorkspace(from: directory)
    return workspace.id
  }

  /// Creates a new tab with the specified agent and working directory.
  func createTab(
    agent: AgentType,
    directory: URL,
    initialPrompt: SavedPrompt? = nil,
    launchArgumentsOverride: [String]? = nil
  ) {
    let workspaceID = resolveWorkspaceID(for: directory)
    let tab = Tab(
      workspaceID: workspaceID,
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
    let workspaceID = resolveWorkspaceID(for: directory)
    let tab = Tab(
      workspaceID: workspaceID,
      agentType: agent,
      workingDirectory: directory,
      mode: .chat,
      resumeSessionId: resumeSessionId
    )
    tabs.append(tab)
    switchToTab(id: tab.id)

    // Send initial prompt if provided.
    if let prompt = initialPrompt,
       !prompt.isEmpty
    {
      tab.chatState?.sendMessage(prompt)
    }
  }

  /// Creates a new Git client tab with the specified working directory.
  func createGitTab(directory: URL) {
    let workspaceID = resolveWorkspaceID(for: directory)
    let tab = Tab(
      workspaceID: workspaceID,
      workingDirectory: directory,
      mode: .git
    )
    tabs.append(tab)
    switchToTab(id: tab.id)
  }

  /// Starts the Telegram bot as a sidebar service.
  func startTelegramBot(directory: URL, startImmediately: Bool = false) {
    guard telegramRuntime == nil else {
      return
    }

    let runtime = TelegramBotRuntime(workingDirectory: directory)
    runtime.delegate = self
    telegramRuntime = runtime

    if startImmediately || configManager.config.telegramAutoStartOnOpen {
      runtime.start()
    }
  }

  /// Stops and removes the Telegram bot runtime.
  func stopTelegramBot() {
    telegramRuntime?.stop()
    telegramRuntime = nil
  }

  /// Closes the tab with the specified ID.
  /// Active tabs and stateless git tabs close immediately.
  /// Inactive terminal/chat tabs prompt for confirmation first.
  func closeTab(id: UUID) {
    guard let tab = tabs.first(where: { $0.id == id }) else {
      return
    }

    if activeTabID == id || tab.mode == .git {
      performCloseTab(id: id)
    } else {
      tabPendingClose = id
    }
  }

  /// Confirms and closes the tab that was pending confirmation.
  func confirmCloseTab() {
    guard let id = tabPendingClose else {
      return
    }

    tabPendingClose = nil
    performCloseTab(id: id)
  }

  /// Cancels the pending tab close.
  func cancelCloseTab() {
    tabPendingClose = nil
  }

  /// Performs the actual tab close: terminates processes, removes from list, selects next tab.
  private func performCloseTab(id: UUID) {
    if tabPendingClose == id {
      tabPendingClose = nil
    }

    guard let index = tabs.firstIndex(where: { $0.id == id }) else {
      return
    }

    let closedTab = tabs[index]

    // Terminate chat process if active.
    closedTab.chatState?.terminateProcess()

    tabs.remove(at: index)

    // If we closed the active tab, switch to another one in the same workspace.
    if activeTabID == id {
      let workspaceTabs = tabs.filter { $0.workspaceID == closedTab.workspaceID }

      if let nextTab = workspaceTabs.first {
        switchToTab(id: nextTab.id)
      } else {
        activeTabID = nil
      }
    }
  }

  /// Switches to the tab with the specified ID.
  func switchToTab(id: UUID) {
    // Deactivate current tab.
    if let currentTab = activeTab {
      currentTab.isActive = false
    }

    // Activate new tab.
    activeTabID = id
    if let newTab = activeTab {
      newTab.isActive = true
      newTab.clearBackgroundActivity()
    }
  }

  /// Moves a tab before another tab within the same workspace.
  func moveTab(id: UUID, before targetID: UUID) {
    guard id != targetID,
          let sourceTab = tabs.first(where: { $0.id == id }),
          let targetTab = tabs.first(where: { $0.id == targetID }),
          sourceTab.workspaceID == targetTab.workspaceID
    else {
      return
    }

    let workspaceID = sourceTab.workspaceID
    var workspaceTabs = tabs.filter { $0.workspaceID == workspaceID }

    guard let sourceIndex = workspaceTabs.firstIndex(where: { $0.id == id }),
          let targetIndex = workspaceTabs.firstIndex(where: { $0.id == targetID })
    else {
      return
    }

    let movedTab = workspaceTabs.remove(at: sourceIndex)
    let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
    workspaceTabs.insert(movedTab, at: insertionIndex)

    replaceTabs(in: workspaceID, with: workspaceTabs)
  }

  /// Moves a tab to the end of its workspace.
  func moveTabToEnd(id: UUID) {
    guard let sourceTab = tabs.first(where: { $0.id == id }) else {
      return
    }

    let workspaceID = sourceTab.workspaceID
    var workspaceTabs = tabs.filter { $0.workspaceID == workspaceID }

    guard let sourceIndex = workspaceTabs.firstIndex(where: { $0.id == id }) else {
      return
    }

    let movedTab = workspaceTabs.remove(at: sourceIndex)
    workspaceTabs.append(movedTab)

    replaceTabs(in: workspaceID, with: workspaceTabs)
  }

  /// Returns the insertion indicator for the current drag target.
  func tabDropIndicator(for draggedTabID: UUID?, targetTabID: UUID?) -> TabDropIndicator {
    guard let draggedTabID,
          let draggedTab = tabs.first(where: { $0.id == draggedTabID })
    else {
      return .none
    }

    if let targetTabID {
      guard targetTabID != draggedTabID,
            let targetTab = tabs.first(where: { $0.id == targetTabID }),
            targetTab.workspaceID == draggedTab.workspaceID,
            targetTab.workspaceID == activeWorkspaceID
      else {
        return .none
      }

      return .before(targetTabID)
    }

    guard draggedTab.workspaceID == activeWorkspaceID else {
      return .none
    }

    return .end
  }

  /// Replaces tabs for a workspace while preserving other workspace positions.
  private func replaceTabs(in workspaceID: UUID, with reorderedTabs: [Tab]) {
    var reorderedIterator = reorderedTabs.makeIterator()

    tabs = tabs.map { tab in
      guard tab.workspaceID == workspaceID else {
        return tab
      }

      return reorderedIterator.next() ?? tab
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
      // terminateProcess() calls store.saveImmediately() internally.
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
      let requiredMode = mode ?? .terminal

      guard tab.mode == requiredMode else {
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
    switch mode {
    case .chat:
      createChatTab(agent: agent, directory: directory)

    case .git:
      createGitTab(directory: directory)

    case .terminal:
      createTab(agent: agent, directory: directory)
    }
  }

  func telegramBotListRelayableTabs() -> [TelegramRelayTabInfo] {
    let registeredIds = Set(TerminalSurfaceRegistry.shared.registeredTabIds())
    return tabs
      .filter { $0.mode == .terminal && $0.agentType != nil && registeredIds.contains($0.id) }
      .compactMap { tab in
        guard let agentType = tab.agentType else {
          return nil
        }

        return TelegramRelayTabInfo(
          id: tab.id,
          name: tab.tabName,
          agentType: agentType,
          directory: tab.workingDirectory,
          isActive: tab.id == activeTabID
        )
      }
  }

  func telegramBotActiveInjectableAITab() -> TelegramRelayTabInfo? {
    guard let tab = activeTab,
          tab.mode == .terminal,
          let agentType = tab.agentType,
          (agentType == .claude || agentType == .opencode)
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
      agentType: agentType,
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

    case .git:
      return "git"
    }
  }
}
