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
}
