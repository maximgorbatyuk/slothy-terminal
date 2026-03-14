import Foundation

/// Status of a file changed in a specific commit.
enum CommitFileStatus: String, Equatable {
  case added = "A"
  case modified = "M"
  case deleted = "D"
  case renamed = "R"
  case copied = "C"
  case typeChange = "T"

  var badge: String { rawValue }
}

/// A file changed in a specific commit.
struct CommitFileChange: Identifiable, Equatable {
  var id: String { path }
  let path: String
  let status: CommitFileStatus

  var filename: String {
    (path as NSString).lastPathComponent
  }
}

/// A node in a hierarchical file tree built from commit changes.
struct CommitFileTreeNode: Identifiable {
  let id: String
  let name: String
  let path: String
  let isDirectory: Bool
  let children: [CommitFileTreeNode]
  let fileChange: CommitFileChange?

  /// Non-nil children for use with OutlineGroup/List children parameter.
  var optionalChildren: [CommitFileTreeNode]? {
    isDirectory ? children : nil
  }

  /// Builds a hierarchical tree from a flat list of changed files.
  /// Directories are sorted before files; both sorted alphabetically.
  static func buildTree(from changes: [CommitFileChange]) -> [CommitFileTreeNode] {
    class MutableNode {
      let name: String
      let path: String
      var childrenMap: [String: MutableNode] = [:]
      var fileChange: CommitFileChange?

      init(name: String, path: String) {
        self.name = name
        self.path = path
      }
    }

    let root = MutableNode(name: "", path: "")

    for change in changes {
      let components = change.path.split(separator: "/").map(String.init)
      var current = root

      for (i, component) in components.enumerated() {
        let childPath = components[0...i].joined(separator: "/")

        if let existing = current.childrenMap[component] {
          current = existing
        } else {
          let node = MutableNode(name: component, path: childPath)
          current.childrenMap[component] = node
          current = node
        }

        if i == components.count - 1 {
          current.fileChange = change
        }
      }
    }

    func convert(_ node: MutableNode) -> [CommitFileTreeNode] {
      node.childrenMap.values
        .sorted { a, b in
          let aIsDir = !a.childrenMap.isEmpty
          let bIsDir = !b.childrenMap.isEmpty

          if aIsDir != bIsDir {
            return aIsDir
          }

          return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        .map { child in
          let isDir = !child.childrenMap.isEmpty && child.fileChange == nil

          return CommitFileTreeNode(
            id: child.path,
            name: child.name,
            path: child.path,
            isDirectory: isDir,
            children: convert(child),
            fileChange: child.fileChange
          )
        }
    }

    return convert(root)
  }

  /// Collects all directory paths in the tree for initial expansion.
  static func allDirectoryPaths(in nodes: [CommitFileTreeNode]) -> Set<String> {
    var result: Set<String> = []

    for node in nodes where node.isDirectory {
      result.insert(node.path)
      result.formUnion(allDirectoryPaths(in: node.children))
    }

    return result
  }
}

/// Tabs in the commit inspector panel.
enum CommitInspectorTab: String, CaseIterable, Identifiable {
  case commit
  case changes
  case fileTree

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .commit:
      return "Commit"

    case .changes:
      return "Changes"

    case .fileTree:
      return "File Tree"
    }
  }
}
