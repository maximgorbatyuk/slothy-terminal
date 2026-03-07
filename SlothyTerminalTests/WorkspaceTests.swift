import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("Workspace")
struct WorkspaceTests {

  @Test("Workspace name matches directory last component")
  func workspaceNameFromDirectory() {
    let dir = URL(fileURLWithPath: "/Users/test/projects/MyProject")
    let workspace = Workspace(directory: dir)

    #expect(workspace.name == "MyProject")
    #expect(workspace.rootDirectory == dir)
  }

  @Test("Workspace ID is unique per instance")
  func workspaceUniqueID() {
    let dir = URL(fileURLWithPath: "/tmp/test")
    let w1 = Workspace(directory: dir)
    let w2 = Workspace(directory: dir)

    #expect(w1.id != w2.id)
  }

  @Test("Workspace is Codable roundtrip")
  func workspaceCodable() throws {
    let dir = URL(fileURLWithPath: "/Users/test/code")
    let original = Workspace(directory: dir)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Workspace.self, from: data)

    #expect(decoded.id == original.id)
    #expect(decoded.name == original.name)
    #expect(decoded.rootDirectory == original.rootDirectory)
  }

  @Test("Tab stores workspaceID")
  @MainActor
  func tabHasWorkspaceID() {
    let workspaceID = UUID()
    let tab = Tab(
      workspaceID: workspaceID,
      agentType: .terminal,
      workingDirectory: URL(fileURLWithPath: "/tmp")
    )

    #expect(tab.workspaceID == workspaceID)
  }
}
