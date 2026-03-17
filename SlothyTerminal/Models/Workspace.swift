import Foundation

/// A workspace groups tabs under a named project context.
/// Empty workspaces may be reused for a newly selected folder.
struct Workspace: Identifiable, Codable {
  let id: UUID
  let name: String
  let rootDirectory: URL

  /// Active split-view state, or nil when in single-tab mode.
  var splitState: WorkspaceSplitState?

  /// Last focused tab ID in this workspace, used to restore focus on workspace switch.
  var lastFocusedTabID: UUID?

  init(id: UUID = UUID(), name: String, rootDirectory: URL) {
    self.id = id
    self.name = name
    self.rootDirectory = rootDirectory
  }

  /// Creates a workspace named after the directory's last path component.
  init(directory: URL) {
    self.init(name: directory.lastPathComponent, rootDirectory: directory)
  }

  // MARK: - Resilient Decoding

  private enum CodingKeys: String, CodingKey {
    case id, name, rootDirectory, splitState, lastFocusedTabID
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    rootDirectory = try c.decode(URL.self, forKey: .rootDirectory)
    splitState = try? c.decode(WorkspaceSplitState.self, forKey: .splitState)
    lastFocusedTabID = try? c.decode(UUID.self, forKey: .lastFocusedTabID)
  }
}
