import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("AppState Workspace")
struct AppStateWorkspaceTests {
  private let dirA = URL(fileURLWithPath: "/tmp/workspace-a")
  private let dirB = URL(fileURLWithPath: "/tmp/workspace-b")
  private let dirC = URL(fileURLWithPath: "/tmp/workspace-c")

  @Test("First tab creates first workspace from selected directory")
  @MainActor
  func firstTabCreatesWorkspace() {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)

    #expect(appState.workspaces.count == 1)
    #expect(appState.activeWorkspace?.name == "workspace-a")
    #expect(appState.activeWorkspace?.rootDirectory == dirA)
    #expect(appState.tabs.count == 1)
    #expect(appState.tabs[0].workspaceID == appState.workspaces[0].id)
  }

  @Test("Additional tab in different folder reuses existing workspace")
  @MainActor
  func additionalTabReusesWorkspace() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let initialWorkspaceID = try #require(appState.activeWorkspaceID)

    appState.createTab(agent: .terminal, directory: dirB)

    #expect(appState.workspaces.count == 1)
    #expect(appState.tabs.count == 2)
    #expect(appState.tabs[0].workspaceID == initialWorkspaceID)
    #expect(appState.tabs[1].workspaceID == initialWorkspaceID)
    #expect(appState.tabs[0].workingDirectory != appState.tabs[1].workingDirectory)
  }

  @Test("closeWorkspace fails while workspace still has tabs")
  @MainActor
  func closeWorkspaceBlockedWithTabs() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let workspaceID = try #require(appState.activeWorkspaceID)

    let result = appState.closeWorkspace(id: workspaceID)

    #expect(result == .hasOpenTabs)
    #expect(appState.workspaces.count == 1)
  }

  @Test("closeWorkspace succeeds after all workspace tabs are closed")
  @MainActor
  func closeWorkspaceSucceedsAfterClosingTabs() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let workspaceID = try #require(appState.activeWorkspaceID)
    let tabID = try #require(appState.activeTabID)

    appState.closeTab(id: tabID)

    #expect(appState.workspaces.count == 1)

    let result = appState.closeWorkspace(id: workspaceID)

    #expect(result == .closed)
    #expect(appState.workspaces.isEmpty)
  }

  @Test("switchWorkspace aligns active tab with selected workspace")
  @MainActor
  func switchWorkspaceAlignsActiveTab() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let firstWorkspaceID = try #require(appState.activeWorkspaceID)
    let firstTabID = try #require(appState.activeTabID)

    let secondWorkspace = appState.createWorkspace(from: dirB)
    appState.createTab(agent: .terminal, directory: dirC)
    let secondTabID = try #require(appState.activeTabID)

    #expect(secondWorkspace.id != firstWorkspaceID)
    #expect(secondTabID != firstTabID)
    #expect(appState.activeWorkspaceID == secondWorkspace.id)

    appState.switchWorkspace(id: firstWorkspaceID)

    #expect(appState.activeWorkspaceID == firstWorkspaceID)
    #expect(appState.activeTabID == firstTabID)
    #expect(appState.activeTab?.workspaceID == firstWorkspaceID)
  }

  @Test("Closing last tab does not auto-delete workspace")
  @MainActor
  func closingLastTabPreservesWorkspace() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let workspaceID = try #require(appState.activeWorkspaceID)
    let tabID = try #require(appState.activeTabID)

    appState.closeTab(id: tabID)

    #expect(appState.tabs.isEmpty)
    #expect(appState.workspaces.count == 1)
    #expect(appState.workspaces[0].id == workspaceID)
  }

  @Test("Creating a tab retargets an empty active workspace")
  @MainActor
  func creatingTabRetargetsEmptyActiveWorkspace() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let workspaceID = try #require(appState.activeWorkspaceID)
    let tabID = try #require(appState.activeTabID)

    appState.closeTab(id: tabID)
    appState.createTab(agent: .terminal, directory: dirB)

    #expect(appState.workspaces.count == 1)
    #expect(appState.activeWorkspaceID == workspaceID)
    #expect(appState.activeWorkspace?.rootDirectory == dirB)
    #expect(appState.activeWorkspace?.name == "workspace-b")
    #expect(appState.activeTab?.workingDirectory == dirB)
    #expect(appState.preferredNewSessionDirectory == dirB)
  }

  @Test("Creating a tab retargets an explicitly empty active workspace")
  @MainActor
  func creatingTabRetargetsExplicitlyEmptyActiveWorkspace() throws {
    let appState = AppState()

    let workspace = appState.createWorkspace(from: dirA)

    appState.createTab(agent: .terminal, directory: dirB)

    #expect(appState.workspaces.count == 1)
    #expect(appState.activeWorkspaceID == workspace.id)
    #expect(appState.activeWorkspace?.rootDirectory == dirB)
    #expect(appState.activeTab?.workingDirectory == dirB)
  }

  @Test("Empty active workspace reuses an existing workspace for the selected folder")
  @MainActor
  func emptyActiveWorkspaceReusesExistingWorkspaceForSelectedFolder() throws {
    let appState = AppState()

    let workspaceA = appState.createWorkspace(from: dirA)
    let workspaceB = appState.createWorkspace(from: dirB)

    appState.switchWorkspace(id: workspaceA.id)
    appState.createTab(agent: .terminal, directory: dirB)

    let newTab = try #require(appState.activeTab)
    #expect(appState.workspaces.count == 1)
    #expect(appState.activeWorkspaceID == workspaceB.id)
    #expect(appState.workspace(for: workspaceA.id) == nil)
    #expect(newTab.workspaceID == workspaceB.id)
  }

  @Test("Creating a Git tab retargets an empty active workspace")
  @MainActor
  func creatingGitTabRetargetsEmptyActiveWorkspace() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let workspaceID = try #require(appState.activeWorkspaceID)
    let tabID = try #require(appState.activeTabID)

    appState.closeTab(id: tabID)
    appState.createGitTab(directory: dirB)

    #expect(appState.workspaces.count == 1)
    #expect(appState.activeWorkspaceID == workspaceID)
    #expect(appState.activeWorkspace?.rootDirectory == dirB)
    #expect(appState.activeTab?.workingDirectory == dirB)
  }

  @Test("Creating a tab in a non-empty active workspace keeps its original folder")
  @MainActor
  func creatingTabInNonEmptyActiveWorkspaceKeepsOriginalFolder() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let workspaceID = try #require(appState.activeWorkspaceID)
    appState.createTab(agent: .terminal, directory: dirB)

    #expect(appState.workspaces.count == 1)
    #expect(appState.activeWorkspaceID == workspaceID)
    #expect(appState.activeWorkspace?.rootDirectory == dirA)
    #expect(appState.activeWorkspace?.name == "workspace-a")
  }

  // MARK: - Workspace creation without tab

  @Test("createWorkspace does not create any tabs")
  @MainActor
  func createWorkspaceDoesNotCreateTab() {
    let appState = AppState()

    appState.createWorkspace(from: dirA)

    #expect(appState.workspaces.count == 1)
    #expect(appState.tabs.isEmpty)
    #expect(appState.activeWorkspaceID == appState.workspaces[0].id)
  }

  // MARK: - Visible tabs filtering

  @Test("visibleTabs returns only tabs from active workspace")
  @MainActor
  func visibleTabsFiltersCorrectly() throws {
    let appState = AppState()

    let workspaceA = appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    let tabA = try #require(appState.activeTabID)

    let workspaceB = appState.createWorkspace(from: dirB)
    appState.createTab(agent: .terminal, directory: dirB)

    /// Active workspace is B, should only see B's tab.
    #expect(appState.visibleTabs.count == 1)
    #expect(appState.visibleTabs[0].workspaceID == workspaceB.id)

    /// Switch to workspace A, should only see A's tab.
    appState.switchWorkspace(id: workspaceA.id)

    #expect(appState.visibleTabs.count == 1)
    #expect(appState.visibleTabs[0].id == tabA)
  }

  @Test("Switching workspace restores only that workspace's tabs")
  @MainActor
  func switchWorkspaceRestoresCorrectTabs() throws {
    let appState = AppState()

    let workspaceA = appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    appState.createTab(agent: .terminal, directory: dirA)

    let workspaceB = appState.createWorkspace(from: dirB)
    appState.createTab(agent: .terminal, directory: dirB)

    /// Workspace B active: 1 visible tab.
    #expect(appState.visibleTabs.count == 1)

    /// Switch to A: 2 visible tabs.
    appState.switchWorkspace(id: workspaceA.id)
    #expect(appState.visibleTabs.count == 2)

    /// Switch back to B: 1 visible tab.
    appState.switchWorkspace(id: workspaceB.id)
    #expect(appState.visibleTabs.count == 1)
  }

  @Test("Empty workspace selection shows no visible tabs")
  @MainActor
  func emptyWorkspaceHasNoVisibleTabs() {
    let appState = AppState()

    /// Create workspace A with a tab.
    let workspaceA = appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)

    /// Create empty workspace B.
    let workspaceB = appState.createWorkspace(from: dirB)

    #expect(appState.activeWorkspaceID == workspaceB.id)
    #expect(appState.visibleTabs.isEmpty)
    #expect(appState.activeTabID == nil)

    /// Switch back to A, tabs reappear.
    appState.switchWorkspace(id: workspaceA.id)
    #expect(appState.visibleTabs.count == 1)
  }

  @Test("New tab created in active workspace belongs to it")
  @MainActor
  func newTabBelongsToActiveWorkspace() throws {
    let appState = AppState()

    let workspaceA = appState.createWorkspace(from: dirA)
    let workspaceB = appState.createWorkspace(from: dirB)

    /// Workspace B is active, create a tab.
    appState.createTab(agent: .terminal, directory: dirC)

    let newTab = try #require(appState.activeTab)
    #expect(newTab.workspaceID == workspaceB.id)

    /// Workspace A should still have no tabs.
    #expect(appState.tabs(in: workspaceA.id).isEmpty)
  }

  @Test("Active workspace root directory is preferred for new sessions")
  @MainActor
  func activeWorkspaceRootDirectoryIsPreferredForNewSessions() {
    let appState = AppState()

    appState.globalWorkingDirectory = dirA
    appState.createWorkspace(from: dirB)

    #expect(appState.preferredNewSessionDirectory == dirB)
  }

  @Test("Global working directory is used when no workspace is active")
  @MainActor
  func globalWorkingDirectoryIsUsedWithoutActiveWorkspace() {
    let appState = AppState()

    appState.globalWorkingDirectory = dirA

    #expect(appState.preferredNewSessionDirectory == dirA)
  }

  @Test("Current context directory prefers active tab over workspace root")
  @MainActor
  func currentContextDirectoryPrefersActiveTab() {
    let appState = AppState()

    appState.globalWorkingDirectory = dirA
    appState.createWorkspace(from: dirB)
    appState.createTab(agent: .terminal, directory: dirC)

    #expect(appState.currentContextDirectory == dirC)
  }

  @Test("Current context directory falls back to active workspace root")
  @MainActor
  func currentContextDirectoryFallsBackToWorkspaceRoot() {
    let appState = AppState()

    appState.globalWorkingDirectory = dirA
    appState.createWorkspace(from: dirB)

    #expect(appState.currentContextDirectory == dirB)
  }

  @Test("Git branch refresh context is stable across terminal busy-idle transitions")
  @MainActor
  func gitBranchRefreshContextStableAcrossBusyIdle() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let tab = try #require(appState.activeTab)
    let idleContext = try #require(appState.gitBranchRefreshContext)

    tab.markTerminalBusy()
    let busyContext = try #require(appState.gitBranchRefreshContext)

    /// Context must not change on busy/idle — only on tab or directory changes.
    #expect(busyContext == idleContext)

    tab.markTerminalIdle()
    let settledContext = try #require(appState.gitBranchRefreshContext)

    #expect(settledContext == idleContext)
  }

  @Test("Visible tab labels are numbered by active workspace order")
  @MainActor
  func visibleTabLabelsAreNumberedByActiveWorkspaceOrder() throws {
    let appState = AppState()

    let workspaceA = appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    let tabA1 = try #require(appState.activeTab)
    appState.createTab(agent: .claude, directory: dirA)
    let tabA2 = try #require(appState.activeTab)

    appState.createWorkspace(from: dirB)
    appState.createGitTab(directory: dirB)

    appState.switchWorkspace(id: workspaceA.id)

    #expect(appState.tabBarLabel(for: tabA1) == "1. Terminal | cli")
    #expect(appState.tabBarLabel(for: tabA2) == "2. Claude | cli")
  }

  @Test("Pending close label uses numbered workspace tab label")
  @MainActor
  func pendingCloseLabelUsesNumberedWorkspaceTabLabel() throws {
    let appState = AppState()

    appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    let firstTab = try #require(appState.activeTab)
    appState.createTab(agent: .claude, directory: dirA)
    let secondTab = try #require(appState.activeTab)

    appState.closeTab(id: firstTab.id)

    #expect(appState.pendingCloseTabLabel == "\"1. Terminal | cli\"")
    #expect(appState.tabBarLabel(for: secondTab) == "2. Claude | cli")
  }

  @Test("Tab bar label uses the last submitted command for plain terminal tabs")
  @MainActor
  func tabBarLabelUsesLastSubmittedCommandForPlainTerminalTab() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)

    let tab = try #require(appState.activeTab)
    tab.updateLastSubmittedCommandLabel(from: "npm run dev")

    #expect(appState.tabBarLabel(for: tab) == "1. npm | cli")
  }

  @Test("Tabs can be reordered within the active workspace")
  @MainActor
  func tabsCanBeReorderedWithinActiveWorkspace() throws {
    let appState = AppState()

    appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    let firstTab = try #require(appState.activeTab)
    appState.createTab(agent: .claude, directory: dirA)
    let secondTab = try #require(appState.activeTab)

    appState.moveTab(id: secondTab.id, before: firstTab.id)

    #expect(appState.visibleTabs.map(\.id) == [secondTab.id, firstTab.id])
    #expect(appState.tabBarLabel(for: secondTab) == "1. Claude | cli")
    #expect(appState.tabBarLabel(for: firstTab) == "2. Terminal | cli")
  }

  @Test("Reordering one workspace does not affect another workspace")
  @MainActor
  func reorderingOneWorkspaceDoesNotAffectAnotherWorkspace() throws {
    let appState = AppState()

    let workspaceA = appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    let tabA1 = try #require(appState.activeTab)

    let workspaceB = appState.createWorkspace(from: dirB)
    appState.createTab(agent: .claude, directory: dirB)
    let tabB1 = try #require(appState.activeTab)
    appState.createTab(agent: .terminal, directory: dirB)
    let tabB2 = try #require(appState.activeTab)

    appState.moveTab(id: tabB2.id, before: tabB1.id)

    #expect(appState.visibleTabs.map(\.id) == [tabB2.id, tabB1.id])

    appState.switchWorkspace(id: workspaceA.id)

    #expect(appState.visibleTabs.map(\.id) == [tabA1.id])
    #expect(appState.activeWorkspaceID == workspaceA.id)
    #expect(workspaceB.id != workspaceA.id)
  }

  @Test("Tab drop indicator only appears for valid workspace drop targets")
  @MainActor
  func tabDropIndicatorOnlyAppearsForValidWorkspaceDropTargets() throws {
    let appState = AppState()

    let workspaceA = appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    let tabA1 = try #require(appState.activeTab)
    appState.createTab(agent: .claude, directory: dirA)
    let tabA2 = try #require(appState.activeTab)

    appState.createWorkspace(from: dirB)
    appState.createTab(agent: .terminal, directory: dirB)
    let tabB1 = try #require(appState.activeTab)

    appState.switchWorkspace(id: workspaceA.id)

    #expect(appState.tabDropIndicator(for: tabA1.id, targetTabID: tabA2.id) == .before(tabA2.id))
    #expect(appState.tabDropIndicator(for: tabA1.id, targetTabID: nil) == .end)
    #expect(appState.tabDropIndicator(for: tabA1.id, targetTabID: tabA1.id) == .none)
    #expect(appState.tabDropIndicator(for: tabA1.id, targetTabID: tabB1.id) == .none)
  }

  @Test("Tab drop indicator visibility matches insertion states")
  @MainActor
  func tabDropIndicatorVisibilityMatchesInsertionStates() {
    #expect(TabDropIndicator.none.isVisible == false)
    #expect(TabDropIndicator.end.isVisible == true)
    #expect(TabDropIndicator.before(UUID()).isVisible == true)
  }

  @Test("Cancelled drag restores original workspace tab order")
  @MainActor
  func cancelledDragRestoresOriginalWorkspaceTabOrder() throws {
    let appState = AppState()

    appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    let firstTab = try #require(appState.activeTab)
    appState.createTab(agent: .claude, directory: dirA)
    let secondTab = try #require(appState.activeTab)

    let originalOrder = appState.visibleTabs.map(\.id)

    appState.beginTabDrag(id: secondTab.id)
    appState.moveTab(id: secondTab.id, before: firstTab.id)

    #expect(appState.visibleTabs.map(\.id) == [secondTab.id, firstTab.id])

    appState.cancelTabDrag()

    #expect(appState.visibleTabs.map(\.id) == originalOrder)
  }

  @Test("Closing tab in workspace selects next tab from same workspace")
  @MainActor
  func closeTabSelectsFromSameWorkspace() throws {
    let appState = AppState()

    let workspaceA = appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    let tabA1 = try #require(appState.activeTabID)
    appState.createTab(agent: .terminal, directory: dirA)
    let tabA2 = try #require(appState.activeTabID)

    appState.createWorkspace(from: dirB)
    appState.createTab(agent: .terminal, directory: dirB)

    /// Switch back to workspace A, close the active tab.
    appState.switchWorkspace(id: workspaceA.id)
    #expect(appState.activeTabID == tabA2 || appState.activeTabID == tabA1)

    let activeTabBeforeClose = try #require(appState.activeTabID)
    appState.closeTab(id: activeTabBeforeClose)

    /// Should select remaining tab from workspace A, not workspace B.
    let newActiveTab = try #require(appState.activeTab)
    #expect(newActiveTab.workspaceID == workspaceA.id)
  }

  // MARK: - Workspace Reordering

  @Test("Swapping adjacent workspaces reorders them")
  @MainActor
  func swapAdjacentWorkspaces() {
    let appState = AppState()

    let wsA = appState.createWorkspace(from: dirA)
    let wsB = appState.createWorkspace(from: dirB)
    let wsC = appState.createWorkspace(from: dirC)

    /// Swap A and B → [B, A, C]
    appState.swapWorkspaces(wsA.id, wsB.id)

    #expect(appState.workspaces.map(\.id) == [wsB.id, wsA.id, wsC.id])
  }

  @Test("Swapping non-adjacent workspaces reorders them")
  @MainActor
  func swapNonAdjacentWorkspaces() {
    let appState = AppState()

    let wsA = appState.createWorkspace(from: dirA)
    let wsB = appState.createWorkspace(from: dirB)
    let wsC = appState.createWorkspace(from: dirC)

    /// Swap A and C → [C, B, A]
    appState.swapWorkspaces(wsA.id, wsC.id)

    #expect(appState.workspaces.map(\.id) == [wsC.id, wsB.id, wsA.id])
  }

  @Test("Swapping workspace with itself is a no-op")
  @MainActor
  func swapWorkspaceSameIdNoOp() {
    let appState = AppState()

    let wsA = appState.createWorkspace(from: dirA)
    appState.createWorkspace(from: dirB)

    let originalOrder = appState.workspaces.map(\.id)
    appState.swapWorkspaces(wsA.id, wsA.id)

    #expect(appState.workspaces.map(\.id) == originalOrder)
  }

  @Test("Swapping workspace with invalid ID is a no-op")
  @MainActor
  func swapWorkspaceInvalidIdNoOp() {
    let appState = AppState()

    let wsA = appState.createWorkspace(from: dirA)
    appState.createWorkspace(from: dirB)

    let originalOrder = appState.workspaces.map(\.id)
    appState.swapWorkspaces(UUID(), wsA.id)

    #expect(appState.workspaces.map(\.id) == originalOrder)
  }

  @Test("Swapping workspaces does not affect active workspace")
  @MainActor
  func swapWorkspacePreservesActiveWorkspace() {
    let appState = AppState()

    appState.createWorkspace(from: dirA)
    let wsB = appState.createWorkspace(from: dirB)
    let wsC = appState.createWorkspace(from: dirC)

    /// wsC is active (last created). Swap it with B.
    appState.swapWorkspaces(wsC.id, wsB.id)

    #expect(appState.activeWorkspaceID == wsC.id)
  }

  @Test("Step-by-step swaps simulate downward drag correctly")
  @MainActor
  func stepByStepDownwardDrag() {
    let appState = AppState()

    let wsA = appState.createWorkspace(from: dirA)
    let wsB = appState.createWorkspace(from: dirB)
    let wsC = appState.createWorkspace(from: dirC)

    /// Drag A downward: A↔B, then A↔C → [B, C, A]
    appState.swapWorkspaces(wsA.id, wsB.id)
    appState.swapWorkspaces(wsA.id, wsC.id)

    #expect(appState.workspaces.map(\.id) == [wsB.id, wsC.id, wsA.id])
  }
}
