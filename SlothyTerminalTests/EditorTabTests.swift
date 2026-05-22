import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("Editor Tab")
struct EditorTabTests {
  /// FileManager.default.temporaryDirectory is already symlink-resolved on
  /// macOS (it points at /private/var/folders/...), so deriving test URLs
  /// from it keeps them stable through `Self.canonicalFileURL`.
  private let projectDir = FileManager.default.temporaryDirectory.appendingPathComponent("editor-project")
  private var fileA: URL { projectDir.appendingPathComponent("main.swift") }
  private var fileB: URL { projectDir.appendingPathComponent("Models/Tab.swift") }

  @Test("Editor tab defaults title to the file name, not the parent directory")
  @MainActor
  func editorTabTitleUsesFileName() {
    let tab = Tab(
      workspaceID: UUID(),
      workingDirectory: fileA.deletingLastPathComponent(),
      mode: .editor,
      fileURL: fileA
    )

    #expect(tab.title == "main.swift")
    #expect(tab.tabName == "main.swift")
  }

  @Test("tabName shows dirty marker for unsaved editor tabs")
  @MainActor
  func tabNameIndicatesDirty() {
    let tab = Tab(
      workspaceID: UUID(),
      workingDirectory: fileA.deletingLastPathComponent(),
      mode: .editor,
      fileURL: fileA
    )

    tab.isDirty = true

    #expect(tab.tabName.hasPrefix("●"))
    #expect(tab.tabName.contains("main.swift"))
  }

  @Test("title and tabName follow fileURL mutations (Save As)")
  @MainActor
  func titleFollowsFileURL() {
    let tab = Tab(
      workspaceID: UUID(),
      workingDirectory: fileA.deletingLastPathComponent(),
      mode: .editor,
      fileURL: fileA
    )

    #expect(tab.title == "main.swift")
    #expect(tab.tabName == "main.swift")

    let renamed = fileA.deletingLastPathComponent().appendingPathComponent("Renamed.swift")
    tab.fileURL = renamed

    #expect(tab.title == "Renamed.swift")
    #expect(tab.tabName == "Renamed.swift")
  }

  @Test("Editor tabs are never marked as executing")
  @MainActor
  func editorTabNotExecuting() {
    let tab = Tab(
      workspaceID: UUID(),
      workingDirectory: fileA.deletingLastPathComponent(),
      mode: .editor,
      fileURL: fileA
    )

    #expect(tab.isExecuting == false)
  }

  @Test("openFileInEditor creates an editor tab and switches to it")
  @MainActor
  func openFileInEditorCreatesTab() {
    let appState = AppState()
    appState.createTab(agent: .terminal, directory: projectDir)

    appState.openFileInEditor(fileA)

    #expect(appState.tabs.count == 2)
    let editorTab = appState.tabs.last
    #expect(editorTab?.mode == .editor)
    #expect(editorTab?.fileURL == fileA)
    #expect(appState.activeTabID == editorTab?.id)
  }

  @Test("openFileInEditor focuses an existing editor tab for the same file")
  @MainActor
  func openFileInEditorFocusesExistingTab() throws {
    let appState = AppState()
    appState.createTab(agent: .terminal, directory: projectDir)

    appState.openFileInEditor(fileA)
    let firstEditorID = try #require(appState.activeTabID)

    /// Move focus elsewhere to prove the second call actually re-switches.
    appState.openFileInEditor(fileB)
    #expect(appState.activeTabID != firstEditorID)

    appState.openFileInEditor(fileA)

    #expect(appState.tabs.filter { $0.mode == .editor }.count == 2)
    #expect(appState.activeTabID == firstEditorID)
  }

  @Test("Editor tab workingDirectory is the workspace root, not the file's parent")
  @MainActor
  func editorTabUsesWorkspaceRootAsWorkingDirectory() throws {
    let appState = AppState()
    appState.createTab(agent: .terminal, directory: projectDir)
    let workspaceRoot = try #require(appState.activeWorkspace?.rootDirectory)

    /// File two levels below the workspace root — different from file.parent.
    let nested = projectDir.appendingPathComponent("a/b/nested.swift")

    appState.openFileInEditor(nested)

    let editorTab = try #require(appState.tabs.last)
    #expect(editorTab.workingDirectory == workspaceRoot)
    #expect(editorTab.workingDirectory != nested.deletingLastPathComponent())
  }

  @Test("Opening a nested file does not retarget an empty active workspace")
  @MainActor
  func openFileDoesNotRetargetEmptyWorkspace() throws {
    let appState = AppState()
    /// Bootstrap: create then close the only tab to leave an empty workspace.
    appState.createTab(agent: .terminal, directory: projectDir)
    let workspaceID = try #require(appState.activeWorkspaceID)
    let originalRoot = try #require(appState.activeWorkspace?.rootDirectory)
    let firstTabID = try #require(appState.tabs.first?.id)
    appState.closeTab(id: firstTabID)
    appState.confirmCloseTab()
    #expect(appState.tabs(in: workspaceID).isEmpty)

    appState.openFileInEditor(projectDir.appendingPathComponent("src/main.swift"))

    #expect(appState.activeWorkspace?.rootDirectory == originalRoot)
  }

  @Test("Canonicalized URL dedupes /tmp vs /private/tmp etc.")
  @MainActor
  func canonicalizedDedupAcrossSymlinkForms() throws {
    let appState = AppState()
    appState.createTab(agent: .terminal, directory: projectDir)

    /// Two URL forms that resolve to the same canonical path: with and
    /// without a `.` segment.
    let parent = projectDir
    let viaDot = parent.appendingPathComponent("./via_dot.swift")
    let direct = parent.appendingPathComponent("via_dot.swift")

    appState.openFileInEditor(viaDot)
    let firstID = try #require(appState.activeTabID)

    appState.openFileInEditor(direct)

    #expect(appState.tabs.filter { $0.mode == .editor }.count == 1)
    #expect(appState.activeTabID == firstID)
  }

  @Test("closeTab on a dirty editor routes through the dirty-editor pending state")
  @MainActor
  func closeTabRoutesDirtyEditorToPendingSheet() throws {
    let appState = AppState()
    appState.createTab(agent: .terminal, directory: projectDir)
    appState.openFileInEditor(fileA)
    let editorID = try #require(appState.activeTabID)
    let editorTab = try #require(appState.tabs.first(where: { $0.id == editorID }))
    editorTab.isDirty = true

    appState.closeTab(id: editorID)

    #expect(appState.tabPendingDirtyEditorClose == editorID)
    #expect(appState.tabs.contains(where: { $0.id == editorID }))
  }

  @Test("closeTab on an inactive dirty editor switches focus before prompting")
  @MainActor
  func closeTabRoutesDirtyInactiveEditorAndFocusesIt() throws {
    let appState = AppState()
    let dirA = FileManager.default.temporaryDirectory.appendingPathComponent("project-a")
    let dirB = FileManager.default.temporaryDirectory.appendingPathComponent("project-b")

    appState.createWorkspaceAndTerminalTab(directory: dirA)
    let workspaceA = try #require(appState.activeWorkspaceID)
    let editorURL = dirA.appendingPathComponent("a.swift")
    appState.openFileInEditor(editorURL)
    let dirtyEditorID = try #require(appState.activeTabID)
    let dirtyEditor = try #require(appState.tabs.first(where: { $0.id == dirtyEditorID }))
    dirtyEditor.isDirty = true

    appState.createWorkspaceAndTerminalTab(directory: dirB)
    let workspaceB = try #require(appState.activeWorkspaceID)
    #expect(workspaceB != workspaceA)

    appState.closeTab(id: dirtyEditorID)

    #expect(appState.activeWorkspaceID == workspaceA)
    #expect(appState.activeTabID == dirtyEditorID)
    #expect(appState.tabPendingDirtyEditorClose == dirtyEditorID)
  }

  @Test("Cancelling a dirty-editor close clears the pending state but keeps the tab")
  @MainActor
  func cancelDirtyEditorCloseKeepsTab() throws {
    let appState = AppState()
    appState.createTab(agent: .terminal, directory: projectDir)
    appState.openFileInEditor(fileA)
    let editorID = try #require(appState.activeTabID)
    let editorTab = try #require(appState.tabs.first(where: { $0.id == editorID }))
    editorTab.isDirty = true
    appState.closeTab(id: editorID)

    appState.cancelDirtyEditorClose()

    #expect(appState.tabPendingDirtyEditorClose == nil)
    #expect(appState.tabs.contains(where: { $0.id == editorID }))
    #expect(editorTab.isDirty == true)
  }

  @Test("discardAndCloseDirtyEditor finishes the close after clearing the dirty flag")
  @MainActor
  func discardAndCloseDirtyEditorRemovesTab() throws {
    let appState = AppState()
    appState.createTab(agent: .terminal, directory: projectDir)
    appState.openFileInEditor(fileA)
    let editorID = try #require(appState.activeTabID)
    let editorTab = try #require(appState.tabs.first(where: { $0.id == editorID }))
    editorTab.isDirty = true
    appState.closeTab(id: editorID)

    appState.discardAndCloseDirtyEditor()

    #expect(appState.tabPendingDirtyEditorClose == nil)
    #expect(appState.tabs.contains(where: { $0.id == editorID }) == false)
  }

  @Test("Opening a file already open in another workspace switches workspaces")
  @MainActor
  func openFileSwitchesWorkspaceToHostTab() throws {
    let appState = AppState()
    let dirX = FileManager.default.temporaryDirectory.appendingPathComponent("project-x")
    let dirY = FileManager.default.temporaryDirectory.appendingPathComponent("project-y")

    appState.createWorkspaceAndTerminalTab(directory: dirX)
    let workspaceX = try #require(appState.activeWorkspaceID)
    let sharedFile = dirX.appendingPathComponent("shared.swift")
    appState.openFileInEditor(sharedFile)
    let editorInX = try #require(appState.activeTabID)

    appState.createWorkspaceAndTerminalTab(directory: dirY)
    let workspaceY = try #require(appState.activeWorkspaceID)
    #expect(workspaceY != workspaceX)

    appState.openFileInEditor(sharedFile)

    #expect(appState.activeWorkspaceID == workspaceX)
    #expect(appState.activeTabID == editorInX)
    #expect(appState.tabs.filter { $0.mode == .editor }.count == 1)
  }

  @Test("Cancelling restores the workspace and tab the user was in before the dirty-close prompt")
  @MainActor
  func cancelDirtyEditorCloseRestoresPriorContext() throws {
    let appState = AppState()
    let dirA = FileManager.default.temporaryDirectory.appendingPathComponent("restore-a")
    let dirB = FileManager.default.temporaryDirectory.appendingPathComponent("restore-b")

    appState.createWorkspaceAndTerminalTab(directory: dirA)
    let workspaceA = try #require(appState.activeWorkspaceID)
    appState.openFileInEditor(dirA.appendingPathComponent("a.swift"))
    let dirtyEditorID = try #require(appState.activeTabID)
    let dirtyEditor = try #require(appState.tabs.first(where: { $0.id == dirtyEditorID }))
    dirtyEditor.isDirty = true

    appState.createWorkspaceAndTerminalTab(directory: dirB)
    let workspaceB = try #require(appState.activeWorkspaceID)
    let priorTabInB = try #require(appState.activeTabID)
    #expect(workspaceB != workspaceA)

    /// Closing the dirty editor from workspace B should switch context to A.
    appState.closeTab(id: dirtyEditorID)
    #expect(appState.activeWorkspaceID == workspaceA)
    #expect(appState.activeTabID == dirtyEditorID)

    /// Cancel returns the user to where they were before the close attempt.
    appState.cancelDirtyEditorClose()
    #expect(appState.activeWorkspaceID == workspaceB)
    #expect(appState.activeTabID == priorTabInB)
    #expect(appState.tabs.contains(where: { $0.id == dirtyEditorID }))
    #expect(dirtyEditor.isDirty == true)
  }

  @Test("Duplicate editor lookup ignores the excluded tab ID")
  @MainActor
  func hasOpenEditorTabHonorsExclusion() throws {
    let appState = AppState()
    appState.createTab(agent: .terminal, directory: projectDir)

    appState.openFileInEditor(fileA)
    let firstEditor = try #require(appState.tabs.last(where: { $0.mode == .editor }))

    appState.openFileInEditor(fileB)
    let secondEditor = try #require(appState.tabs.last(where: { $0.mode == .editor }))

    #expect(appState.hasOpenEditorTab(for: fileA, excludingTabID: firstEditor.id) == false)
    #expect(appState.hasOpenEditorTab(for: fileA, excludingTabID: secondEditor.id) == true)
  }
}
