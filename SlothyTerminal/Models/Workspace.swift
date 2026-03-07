import Foundation

/// A workspace groups tabs under a named project context.
struct Workspace: Identifiable, Codable {
  let id: UUID
  let name: String
  let rootDirectory: URL

  init(id: UUID = UUID(), name: String, rootDirectory: URL) {
    self.id = id
    self.name = name
    self.rootDirectory = rootDirectory
  }

  /// Creates a workspace named after the directory's last path component.
  init(directory: URL) {
    self.init(name: directory.lastPathComponent, rootDirectory: directory)
  }
}
