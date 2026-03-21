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
  case startupPageSplit
  case folderSelector(AgentType)

  case settings

  var id: String {
    switch self {
    case .startupPage:
      return "startupPage"
    case .startupPageSplit:
      return "startupPageSplit"
    case .folderSelector(let agent):
      return "folderSelector-\(agent.rawValue)"
    case .settings:
      return "settings"
    }
  }
}

/// Input that determines when the status bar should re-fetch the git branch.
/// Keyed only on tab identity and directory — not terminal busy state.
struct GitBranchRefreshContext: Equatable {
  let tabID: UUID
  let workingDirectory: URL
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

private struct TabDragSnapshot {
  let draggedTabID: UUID
  let workspaceID: UUID
  let orderedTabIDs: [UUID]
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
      workingDirectory: activeTab.workingDirectory
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

  private var tabDragSnapshot: TabDragSnapshot?

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

    // Save focus and deactivate tabs in the outgoing workspace
    // BEFORE changing activeWorkspaceID, so deactivateCurrentSplitTabs()
    // can still read the outgoing workspace's split state.
    if let outgoingID = activeWorkspaceID, let focusedID = activeTabID {
      updateWorkspace(id: outgoingID) { $0.lastFocusedTabID = focusedID }
      deactivateCurrentSplitTabs()
    }

    activeWorkspaceID = id

    // If current active tab already belongs to this workspace, keep it.
    if let current = activeTab, current.workspaceID == id {
      return
    }

    // Restore last focused tab, or fall back to first tab.
    let workspace = workspaces.first { $0.id == id }

    if let lastFocused = workspace?.lastFocusedTabID,
       tabs.contains(where: { $0.id == lastFocused && $0.workspaceID == id })
    {
      switchToTab(id: lastFocused)
    } else if let firstTab = tabs.first(where: { $0.workspaceID == id }) {
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
  /// Retargets the active workspace when it is empty and a new directory is selected.
  /// Creates the first workspace from the directory if none exist;
  /// otherwise returns the active (or first) workspace ID.
  private func resolveWorkspaceID(for directory: URL) -> UUID {
    if let activeWorkspaceID = resolvedActiveWorkspaceID(for: directory) {
      return activeWorkspaceID
    }

    if let first = workspaces.first {
      activeWorkspaceID = first.id
      return first.id
    }

    let workspace = createWorkspace(from: directory)
    return workspace.id
  }

  private func resolvedActiveWorkspaceID(for directory: URL) -> UUID? {
    guard let activeWorkspace else {
      return nil
    }

    guard !hasTabs(in: activeWorkspace.id) else {
      return activeWorkspace.id
    }

    if let existingWorkspace = workspaces.first(where: { $0.rootDirectory == directory }),
       existingWorkspace.id != activeWorkspace.id
    {
      let orphanedID = activeWorkspace.id
      workspaces.removeAll { $0.id == orphanedID }
      activeWorkspaceID = existingWorkspace.id
      return existingWorkspace.id
    }

    retargetWorkspace(id: activeWorkspace.id, to: directory)
    return activeWorkspace.id
  }

  private func retargetWorkspace(id: UUID, to directory: URL) {
    guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
      return
    }

    guard workspaces[index].rootDirectory != directory else {
      return
    }

    workspaces[index] = Workspace(
      id: id,
      name: directory.lastPathComponent,
      rootDirectory: directory
    )
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

  /// Closes the tab with the specified ID.
  /// Active tabs and stateless git tabs close immediately.
  /// Inactive terminal/chat tabs prompt for confirmation first.
  func closeTab(id: UUID) {
    guard let tab = tabs.first(where: { $0.id == id }) else {
      return
    }

    if activeTabID == id || tab.mode == .git || isTabVisibleInSplit(id) {
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

    // Heal split if the closed tab was part of one.
    healSplitAfterRemoval(tabID: id, workspaceID: closedTab.workspaceID)

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
  /// When a split is active: if the tab is already visible in the split, just move focus;
  /// if the tab is not in the split, replace the currently focused pane with it.
  func switchToTab(id: UUID) {
    guard let newTab = tabs.first(where: { $0.id == id }) else {
      return
    }

    // Deactivate current tab (and its split partner if any).
    deactivateCurrentSplitTabs()

    // Split-aware selection: if this workspace has a split...
    if let wsIndex = workspaces.firstIndex(where: { $0.id == newTab.workspaceID }),
       let split = workspaces[wsIndex].splitState
    {
      if split.contains(id) {
        // Tab is already visible in split — just move focus.
      } else if let focusedID = activeTabID, split.contains(focusedID) {
        // Replace the focused pane with the new tab.
        if let updated = split.replacing(focusedID, with: id) {
          workspaces[wsIndex].splitState = updated
        }
      }
    }

    // Activate new tab.
    activeTabID = id
    newTab.isActive = true
    newTab.clearBackgroundActivity()

    // Mark both split-visible tabs as active to suppress background-activity indicators.
    activateSplitPartner(of: id)

    // Track last focused tab in the workspace.
    if let wsID = activeWorkspaceID {
      updateWorkspace(id: wsID) { $0.lastFocusedTabID = id }
    }
  }

  /// Deactivates the current active tab and its split partner.
  private func deactivateCurrentSplitTabs() {
    guard let currentTab = activeTab else {
      return
    }

    currentTab.isActive = false

    // Also deactivate the split partner if one exists.
    if let split = activeSplitState,
       let partnerID = split.otherTab(than: currentTab.id),
       let partner = tabs.first(where: { $0.id == partnerID })
    {
      partner.isActive = false
    }
  }

  /// Marks the split partner of the given tab as active (visible).
  private func activateSplitPartner(of tabID: UUID) {
    guard let wsID = activeWorkspaceID,
          let workspace = workspaces.first(where: { $0.id == wsID }),
          let split = workspace.splitState,
          let partnerID = split.otherTab(than: tabID),
          let partner = tabs.first(where: { $0.id == partnerID })
    else {
      return
    }

    partner.isActive = true
    partner.clearBackgroundActivity()
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

  /// Captures the original workspace order before drag reordering begins.
  func beginTabDrag(id: UUID) {
    guard let draggedTab = tabs.first(where: { $0.id == id }) else {
      return
    }

    let workspaceID = draggedTab.workspaceID
    let orderedTabIDs = tabs
      .filter { $0.workspaceID == workspaceID }
      .map(\.id)

    tabDragSnapshot = TabDragSnapshot(
      draggedTabID: id,
      workspaceID: workspaceID,
      orderedTabIDs: orderedTabIDs
    )
  }

  /// Restores the original order if a drag ends without a committed drop.
  func cancelTabDrag() {
    guard let snapshot = tabDragSnapshot else {
      return
    }

    restoreWorkspaceTabOrder(for: snapshot)
    tabDragSnapshot = nil
  }

  /// Clears drag snapshot after a successful drop.
  func completeTabDrag() {
    tabDragSnapshot = nil
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

  // MARK: - Workspace Reordering

  /// Swaps two workspaces in the list. Used for drag-drop reordering in a vertical list,
  /// where step-by-step swaps produce the correct final order regardless of drag direction.
  func swapWorkspaces(_ idA: UUID, _ idB: UUID) {
    guard idA != idB,
          let indexA = workspaces.firstIndex(where: { $0.id == idA }),
          let indexB = workspaces.firstIndex(where: { $0.id == idB })
    else {
      return
    }

    workspaces.swapAt(indexA, indexB)
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

  /// Restores a workspace to a previously captured tab order.
  private func restoreWorkspaceTabOrder(for snapshot: TabDragSnapshot) {
    let tabsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
    let restoredTabs = snapshot.orderedTabIDs.compactMap { tabsByID[$0] }
    replaceTabs(in: snapshot.workspaceID, with: restoredTabs)
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

  /// Terminates all active PTY sessions.
  /// Called during app quit to ensure child processes are cleaned up.
  func terminateAllSessions() {
  }
}

// MARK: - Split View

extension AppState {
  /// The split state of the currently active workspace, if any.
  var activeSplitState: WorkspaceSplitState? {
    guard let activeWorkspaceID else {
      return nil
    }

    return workspaces.first { $0.id == activeWorkspaceID }?.splitState
  }

  /// Whether the active workspace is currently in split-view mode.
  var isSplitActive: Bool {
    activeSplitState != nil
  }

  /// Whether the given tab is currently visible in the active split.
  func isTabVisibleInSplit(_ tabID: UUID) -> Bool {
    activeSplitState?.contains(tabID) ?? false
  }

  /// Creates or updates a split in the active workspace.
  /// Pairs the current focused tab with the given second tab ID.
  /// Both tabs must belong to the active workspace.
  func createSplit(with secondTabID: UUID) {
    guard let focusedID = activeTabID,
          focusedID != secondTabID,
          let focusedTab = tabs.first(where: { $0.id == focusedID }),
          let secondTab = tabs.first(where: { $0.id == secondTabID }),
          focusedTab.workspaceID == secondTab.workspaceID,
          let wsID = activeWorkspaceID,
          focusedTab.workspaceID == wsID
    else {
      return
    }

    let split = WorkspaceSplitState(leftTabID: focusedID, rightTabID: secondTabID)
    updateWorkspace(id: wsID) { $0.splitState = split }
  }

  /// Creates a new tab and places it into the split alongside the focused tab.
  /// If no split exists, creates one. If a split already exists, replaces the focused pane.
  func createTabInSplit(
    agent: AgentType,
    directory: URL,
    initialPrompt: SavedPrompt? = nil,
    launchArgumentsOverride: [String]? = nil
  ) {
    guard let focusedID = activeTabID else {
      createTab(agent: agent, directory: directory, initialPrompt: initialPrompt, launchArgumentsOverride: launchArgumentsOverride)
      return
    }

    let workspaceID = resolveWorkspaceID(for: directory)
    let tab = Tab(
      workspaceID: workspaceID,
      agentType: agent,
      workingDirectory: directory,
      initialPrompt: initialPrompt,
      launchArgumentsOverride: launchArgumentsOverride
    )
    insertTabAdjacentTo(focusedID, newTab: tab)
    wireSplit(focusedTabID: focusedID, newTabID: tab.id, workspaceID: workspaceID)
    switchToTab(id: tab.id)
  }

  /// Creates a new git tab and places it into the split.
  func createGitTabInSplit(directory: URL) {
    guard let focusedID = activeTabID else {
      createGitTab(directory: directory)
      return
    }

    let workspaceID = resolveWorkspaceID(for: directory)
    let tab = Tab(
      workspaceID: workspaceID,
      workingDirectory: directory,
      mode: .git
    )
    insertTabAdjacentTo(focusedID, newTab: tab)
    wireSplit(focusedTabID: focusedID, newTabID: tab.id, workspaceID: workspaceID)
    switchToTab(id: tab.id)
  }

  /// Inserts a new tab right after the given anchor tab in the tabs array.
  /// Falls back to append if the anchor is not found.
  private func insertTabAdjacentTo(_ anchorID: UUID, newTab: Tab) {
    if let anchorIndex = tabs.firstIndex(where: { $0.id == anchorID }) {
      tabs.insert(newTab, at: anchorIndex + 1)
    } else {
      tabs.append(newTab)
    }
  }

  /// Wires a new tab into the split alongside the focused tab.
  /// Creates a new split if none exists, or replaces the focused pane in an existing split.
  private func wireSplit(focusedTabID: UUID, newTabID: UUID, workspaceID: UUID) {
    guard let wsIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
      return
    }

    if let existing = workspaces[wsIndex].splitState {
      if let updated = existing.replacing(focusedTabID, with: newTabID) {
        workspaces[wsIndex].splitState = updated
      }
    } else {
      workspaces[wsIndex].splitState = WorkspaceSplitState(
        leftTabID: focusedTabID,
        rightTabID: newTabID
      )
    }
  }

  /// Opens an existing tab in split view alongside the current focused tab.
  /// If a split already exists, replaces the focused pane with the given tab.
  func openInSplitView(tabID: UUID) {
    guard let focusedID = activeTabID,
          focusedID != tabID
    else {
      return
    }

    createSplit(with: tabID)
  }

  /// Detaches a tab from the split, collapsing back to single-tab mode.
  /// The tab stays alive as a normal workspace tab. Focus stays on the active tab.
  func detachFromSplit(tabID: UUID) {
    guard let wsID = activeWorkspaceID,
          let wsIndex = workspaces.firstIndex(where: { $0.id == wsID }),
          let split = workspaces[wsIndex].splitState,
          split.contains(tabID)
    else {
      return
    }

    // Deactivate the split partner before collapsing.
    if let partnerID = split.otherTab(than: tabID),
       let partner = tabs.first(where: { $0.id == partnerID })
    {
      partner.isActive = false
    }

    // Collapse the split. Focus stays on the current activeTabID.
    workspaces[wsIndex].splitState = nil

    // Ensure the active tab is properly activated in single mode.
    if let currentID = activeTabID {
      switchToTab(id: currentID)
    }
  }

  /// Closes a split pane: closes the tab and heals the split.
  func closeSplitPane(tabID: UUID) {
    closeTab(id: tabID)
  }

  /// Shows the startup page in split-destination mode.
  func showStartupPageForSplit() {
    guard activeTabID != nil else {
      // No focused tab — use normal creation.
      showStartupPage()
      return
    }

    activeModal = .startupPageSplit
  }

  /// Removes a tab from the split state and collapses if needed.
  /// Called before the tab is actually removed from the tabs array.
  private func healSplitAfterRemoval(tabID: UUID, workspaceID: UUID) {
    guard let wsIndex = workspaces.firstIndex(where: { $0.id == workspaceID }),
          let split = workspaces[wsIndex].splitState,
          split.contains(tabID)
    else {
      return
    }

    // Collapse the split — the remaining tab becomes the sole visible tab.
    workspaces[wsIndex].splitState = nil

    // If the remaining tab exists, make sure focus goes to it.
    if let remainingID = split.remaining(after: tabID),
       tabs.contains(where: { $0.id == remainingID })
    {
      if activeTabID == tabID {
        switchToTab(id: remainingID)
      }
    }
  }

  /// Validates split state integrity. Clears invalid splits where a tab no longer exists.
  func validateSplitStates() {
    let allTabIDs = Set(tabs.map(\.id))

    for index in workspaces.indices {
      guard let split = workspaces[index].splitState else {
        continue
      }

      if !allTabIDs.contains(split.leftTabID) || !allTabIDs.contains(split.rightTabID) {
        workspaces[index].splitState = nil
      }
    }
  }

  /// Mutates the workspace at the given ID.
  private func updateWorkspace(id: UUID, _ mutation: (inout Workspace) -> Void) {
    guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
      return
    }

    mutation(&workspaces[index])
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

