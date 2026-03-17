import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("WorkspaceSplitState")
struct WorkspaceSplitStateTests {
  private let tabA = UUID()
  private let tabB = UUID()
  private let tabC = UUID()

  @Test("contains returns true for both members")
  func containsBothMembers() {
    let split = WorkspaceSplitState(leftTabID: tabA, rightTabID: tabB)

    #expect(split.contains(tabA))
    #expect(split.contains(tabB))
    #expect(!split.contains(tabC))
  }

  @Test("otherTab returns the opposite member")
  func otherTabReturnsOpposite() {
    let split = WorkspaceSplitState(leftTabID: tabA, rightTabID: tabB)

    #expect(split.otherTab(than: tabA) == tabB)
    #expect(split.otherTab(than: tabB) == tabA)
    #expect(split.otherTab(than: tabC) == nil)
  }

  @Test("replacing left tab produces updated state")
  func replacingLeftTab() throws {
    let split = WorkspaceSplitState(leftTabID: tabA, rightTabID: tabB)
    let updated = try #require(split.replacing(tabA, with: tabC))

    #expect(updated.leftTabID == tabC)
    #expect(updated.rightTabID == tabB)
  }

  @Test("replacing right tab produces updated state")
  func replacingRightTab() throws {
    let split = WorkspaceSplitState(leftTabID: tabA, rightTabID: tabB)
    let updated = try #require(split.replacing(tabB, with: tabC))

    #expect(updated.leftTabID == tabA)
    #expect(updated.rightTabID == tabC)
  }

  @Test("replacing with already-visible tab returns nil")
  func replacingWithExistingMemberReturnsNil() {
    let split = WorkspaceSplitState(leftTabID: tabA, rightTabID: tabB)

    #expect(split.replacing(tabA, with: tabB) == nil)
    #expect(split.replacing(tabB, with: tabA) == nil)
  }

  @Test("replacing non-member returns nil")
  func replacingNonMemberReturnsNil() {
    let split = WorkspaceSplitState(leftTabID: tabA, rightTabID: tabB)

    #expect(split.replacing(tabC, with: UUID()) == nil)
  }

  @Test("remaining after removal returns the other tab")
  func remainingAfterRemoval() {
    let split = WorkspaceSplitState(leftTabID: tabA, rightTabID: tabB)

    #expect(split.remaining(after: tabA) == tabB)
    #expect(split.remaining(after: tabB) == tabA)
    #expect(split.remaining(after: tabC) == nil)
  }

  @Test("tabIDs returns both members as a set")
  func tabIDsSet() {
    let split = WorkspaceSplitState(leftTabID: tabA, rightTabID: tabB)

    #expect(split.tabIDs == [tabA, tabB])
  }

  @Test("Codable roundtrip preserves state")
  func codableRoundtrip() throws {
    let original = WorkspaceSplitState(leftTabID: tabA, rightTabID: tabB)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(WorkspaceSplitState.self, from: data)

    #expect(decoded == original)
  }
}

@Suite("AppState Split View")
struct AppStateSplitTests {
  private let dirA = URL(fileURLWithPath: "/tmp/split-a")
  private let dirB = URL(fileURLWithPath: "/tmp/split-b")

  @Test("createSplit from active tab + new second tab")
  @MainActor
  func createSplitFromActiveTab() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let tab1 = try #require(appState.activeTabID)

    appState.createTab(agent: .terminal, directory: dirA)
    let tab2 = try #require(appState.activeTabID)

    appState.switchToTab(id: tab1)
    appState.createSplit(with: tab2)

    let split = try #require(appState.activeSplitState)
    #expect(split.leftTabID == tab1)
    #expect(split.rightTabID == tab2)
    #expect(appState.isSplitActive)
  }

  @Test("converting existing second tab into split via openInSplitView")
  @MainActor
  func openExistingTabInSplitView() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let tab1 = try #require(appState.activeTabID)

    appState.createTab(agent: .terminal, directory: dirA)
    let tab2 = try #require(appState.activeTabID)

    // tab2 is focused, open tab1 in split
    appState.openInSplitView(tabID: tab1)

    let split = try #require(appState.activeSplitState)
    #expect(split.contains(tab1))
    #expect(split.contains(tab2))
  }

  @Test("selecting a non-visible tab replaces focused pane")
  @MainActor
  func selectingNonVisibleTabReplacesFocusedPane() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let tab1 = try #require(appState.activeTabID)

    appState.createTab(agent: .terminal, directory: dirA)
    let tab2 = try #require(appState.activeTabID)

    appState.createTab(agent: .terminal, directory: dirA)
    let tab3 = try #require(appState.activeTabID)

    // Create split with tab1 + tab2, focus tab2
    appState.switchToTab(id: tab2)
    appState.createSplit(with: tab1)

    // Now select tab3 — should replace the focused pane (tab2)
    appState.switchToTab(id: tab3)

    let split = try #require(appState.activeSplitState)
    #expect(split.contains(tab1))
    #expect(split.contains(tab3))
    #expect(!split.contains(tab2))
    #expect(appState.activeTabID == tab3)
  }

  @Test("selecting a visible split tab only changes focus")
  @MainActor
  func selectingVisibleSplitTabOnlyChangesFocus() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let tab1 = try #require(appState.activeTabID)

    appState.createTab(agent: .terminal, directory: dirA)
    let tab2 = try #require(appState.activeTabID)

    appState.switchToTab(id: tab1)
    appState.createSplit(with: tab2)

    // Focus is on tab1, click tab2
    appState.switchToTab(id: tab2)

    let split = try #require(appState.activeSplitState)
    #expect(split.leftTabID == tab1)
    #expect(split.rightTabID == tab2)
    #expect(appState.activeTabID == tab2)
  }

  @Test("moving a pane back to tab collapses correctly")
  @MainActor
  func detachPaneCollapsesCorrectly() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let tab1 = try #require(appState.activeTabID)

    appState.createTab(agent: .terminal, directory: dirA)
    let tab2 = try #require(appState.activeTabID)

    appState.switchToTab(id: tab1)
    appState.createSplit(with: tab2)
    #expect(appState.isSplitActive)

    // Detach tab1 — split collapses, focus stays on tab1 (active tab).
    appState.detachFromSplit(tabID: tab1)

    #expect(!appState.isSplitActive)
    #expect(appState.activeSplitState == nil)
    #expect(appState.activeTabID == tab1)
    // Both tabs still exist.
    #expect(appState.tabs.count == 2)
  }

  @Test("closing one split pane heals layout and keeps remaining session alive")
  @MainActor
  func closingOneSplitPaneHealsLayout() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let tab1 = try #require(appState.activeTabID)

    appState.createTab(agent: .terminal, directory: dirA)
    let tab2 = try #require(appState.activeTabID)

    appState.switchToTab(id: tab1)
    appState.createSplit(with: tab2)
    #expect(appState.isSplitActive)

    // Close tab1 (focused pane)
    appState.closeSplitPane(tabID: tab1)

    #expect(!appState.isSplitActive)
    #expect(appState.tabs.count == 1)
    #expect(appState.tabs[0].id == tab2)
    #expect(appState.activeTabID == tab2)
  }

  @Test("createTabInSplit creates split when none exists")
  @MainActor
  func createTabInSplitCreatesNewSplit() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let tab1 = try #require(appState.activeTabID)

    #expect(!appState.isSplitActive)

    appState.createTabInSplit(agent: .terminal, directory: dirA)
    let tab2 = try #require(appState.activeTabID)

    #expect(tab2 != tab1)
    let split = try #require(appState.activeSplitState)
    #expect(split.leftTabID == tab1)
    #expect(split.rightTabID == tab2)
  }

  @Test("createTabInSplit replaces focused pane in existing split")
  @MainActor
  func createTabInSplitReplacesExistingSplit() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let tab1 = try #require(appState.activeTabID)

    appState.createTab(agent: .terminal, directory: dirA)
    let tab2 = try #require(appState.activeTabID)

    appState.switchToTab(id: tab1)
    appState.createSplit(with: tab2)

    // tab1 is focused, create new tab in split — replaces tab1
    appState.createTabInSplit(agent: .terminal, directory: dirA)
    let tab3 = try #require(appState.activeTabID)

    let split = try #require(appState.activeSplitState)
    #expect(split.contains(tab3))
    #expect(split.contains(tab2))
    #expect(!split.contains(tab1))
    // tab1 still exists as a normal tab
    #expect(appState.tabs.contains { $0.id == tab1 })
  }

  @Test("cross-workspace split is rejected")
  @MainActor
  func crossWorkspaceSplitIsRejected() throws {
    let appState = AppState()

    appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)

    let workspaceB = appState.createWorkspace(from: dirB)
    appState.createTab(agent: .terminal, directory: dirB)
    let tabB = try #require(appState.activeTabID)

    appState.switchWorkspace(id: workspaceB.id)

    // Try to split with tab from workspace A — should be rejected
    let tabA = appState.tabs.first { $0.workspaceID != workspaceB.id }!
    appState.openInSplitView(tabID: tabA.id)

    #expect(!appState.isSplitActive)
    #expect(appState.activeTabID == tabB)
  }

  @Test("validateSplitStates clears invalid split")
  @MainActor
  func validateSplitStatesClearsInvalid() throws {
    let appState = AppState()

    appState.createTab(agent: .terminal, directory: dirA)
    let tab1 = try #require(appState.activeTabID)

    appState.createTab(agent: .terminal, directory: dirA)
    let tab2 = try #require(appState.activeTabID)

    appState.switchToTab(id: tab1)
    appState.createSplit(with: tab2)
    #expect(appState.isSplitActive)

    // Manually remove a tab to simulate corruption
    appState.tabs.removeAll { $0.id == tab2 }
    appState.validateSplitStates()

    #expect(!appState.isSplitActive)
  }

  @Test("workspace switch restores last focused tab")
  @MainActor
  func workspaceSwitchRestoresLastFocusedTab() throws {
    let appState = AppState()

    let workspaceA = appState.createWorkspace(from: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    appState.createTab(agent: .terminal, directory: dirA)
    let tabA2 = try #require(appState.activeTabID)

    let workspaceB = appState.createWorkspace(from: dirB)
    appState.createTab(agent: .terminal, directory: dirB)

    // Switch back to A — should restore tabA2 as last focused
    appState.switchWorkspace(id: workspaceA.id)
    #expect(appState.activeTabID == tabA2)

    // Switch to B and back
    appState.switchWorkspace(id: workspaceB.id)
    appState.switchWorkspace(id: workspaceA.id)
    #expect(appState.activeTabID == tabA2)
  }
}
